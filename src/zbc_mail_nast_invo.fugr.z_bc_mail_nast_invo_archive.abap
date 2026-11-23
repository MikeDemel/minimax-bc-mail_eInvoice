FUNCTION z_bc_mail_nast_invo_archive.
*"----------------------------------------------------------------------
*"*"Lokale Schnittstelle:
*"  IMPORTING
*"     VALUE(SAP_OBJECT) TYPE  SAEANWDID
*"     VALUE(OBJECT_ID) TYPE  SAEOBJID
*"     VALUE(AR_OBJECT) TYPE  SAEOBJART
*"     VALUE(DOCUMENTS) TYPE  ZBC_MAIL_NAST_INVO_ARC_DOCS
*"----------------------------------------------------------------------
  " Zeile 1 (Rechnung) wird unveraendert abgelegt, die Anhaenge ab Zeile 2
  " zusammengefuehrt als zweites Dokument. Die Rechnung selbst wird nicht
  " gemergt: Das PDF aus /IX2/EINV_GET_PDF lehnt ADS ab (RC 107).
  " Fehler brechen die tRFC-LUW ab: Eintrag in SM58, dort wiederholbar.
  DATA archive_contents TYPE STANDARD TABLE OF xstring WITH EMPTY KEY.
  DATA binary_content   TYPE STANDARD TABLE OF tbl1024 WITH EMPTY KEY.
  DATA length           TYPE i.
  DATA merged_pdf       TYPE xstring.
  DATA merge_result     TYPE i.
  DATA error_index      TYPE i.

  IF documents IS INITIAL.
    RETURN.
  ENDIF.

  archive_contents = VALUE #( ( documents[ 1 ]-content ) ).

  " Erst zusammenfuehren, dann ablegen: Scheitert der Merge, ist noch
  " nichts im Content-Repository gespeichert.
  CASE lines( documents ).
    WHEN 1.
      " Keine Anhaenge
    WHEN 2.
      INSERT documents[ 2 ]-content INTO TABLE archive_contents.
    WHEN OTHERS.
      TRY.
          DATA(merger) = NEW cl_rspo_pdf_merge( ).
          LOOP AT documents FROM 2 REFERENCE INTO DATA(document).
            merger->add_document( document->content ).
          ENDLOOP.

          merger->merge_documents( IMPORTING merged_document = merged_pdf
                                             rc              = merge_result ).
        CATCH cx_rspo_pdf_merge INTO DATA(merge_error).
          " Ohne CATCH gaebe es einen Kurzdump statt eines lesbaren SM58-Eintrags
          MESSAGE merge_error TYPE 'E'.
      ENDTRY.

      IF merge_result <> 0 OR merged_pdf IS INITIAL.
        merger->get_err_doc_index( IMPORTING index = error_index ).
        " Index des Mergers zaehlt ab dem ersten Anhang, gemeldet wird die
        " Zeile in DOCUMENTS. Objekt-ID zuletzt: sie ist bis zu 50 Zeichen
        " lang und wuerde den SM58-Statustext sonst abschneiden.
        error_index = error_index + 1.
        DATA(document_count) = lines( documents ).
        MESSAGE e014(zbc_mail_nast_invo) WITH error_index document_count merge_result object_id.
      ENDIF.

      INSERT merged_pdf INTO TABLE archive_contents.
  ENDCASE.

  LOOP AT archive_contents INTO DATA(content).
    CLEAR: binary_content, length.

    CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
      EXPORTING buffer        = content
      IMPORTING output_length = length
      TABLES    binary_tab    = binary_content.

    " Typ von FLENGTH in SE37 gegenpruefen (LIKE SAPB-LENGTH)
    DATA(file_length) = CONV sapb-length( length ).

    CALL FUNCTION 'ARCHIV_CREATE_TABLE'
      EXPORTING  ar_object       = ar_object
                 object_id       = object_id
                 sap_object      = sap_object
                 flength         = file_length
                 doc_type        = 'PDF'
      TABLES     binarchivobject = binary_content
      EXCEPTIONS OTHERS          = 1.

    IF sy-subrc <> 0.
      " Bereits geschriebene Verknuepfungen dieser LUW werden zurueckgerollt
      MESSAGE e010(zbc_mail_nast_invo) WITH object_id ar_object.
    ENDIF.
  ENDLOOP.
ENDFUNCTION.
