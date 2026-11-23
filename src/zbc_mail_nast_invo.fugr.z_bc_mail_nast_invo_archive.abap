FUNCTION z_bc_mail_nast_invo_archive.
*"----------------------------------------------------------------------
*"*"Lokale Schnittstelle:
*"  IMPORTING
*"     VALUE(SAP_OBJECT) TYPE  SAEANWDID
*"     VALUE(OBJECT_ID) TYPE  SAEOBJID
*"     VALUE(AR_OBJECT) TYPE  SAEOBJART
*"     VALUE(INVOICE_NUMBER) TYPE  VBELN_VF
*"     VALUE(DOCUMENTS) TYPE  ZBC_MAIL_NAST_INVO_ARC_DOCS
*"----------------------------------------------------------------------
  " Zeile 1 (Rechnung) wird unveraendert abgelegt, die Anhaenge ab Zeile 2
  " zusammengefuehrt als zweites Dokument. Die Rechnung selbst wird nicht
  " gemergt: Das PDF aus /IX2/EINV_GET_PDF lehnt ADS ab (RC 107).
  " Beide Dokumente werden vor der Ablage nach PDF/A-3b konvertiert.
  " Beschreibung und Dateiname landen in TOAAT und erscheinen in der
  " Anlagenliste statt des Dokumentart-Textes.
  " Fehler brechen die tRFC-LUW ab: Eintrag in SM58, dort wiederholbar.
  TYPES: BEGIN OF archive_document,
           content     TYPE xstring,
           description TYPE toaat-descr,
           file_name   TYPE toaat-filename,
         END OF archive_document.

  DATA archive_documents TYPE STANDARD TABLE OF archive_document WITH EMPTY KEY.
  DATA attachments_pdf   TYPE xstring.
  DATA merge_result      TYPE i.
  DATA error_index       TYPE i.
  DATA description       TYPE toaat-descr.

  IF documents IS INITIAL.
    RETURN.
  ENDIF.

  DATA(invoice_number_text) = |{ invoice_number ALPHA = OUT }|.

  MESSAGE i015(zbc_mail_nast_invo) WITH invoice_number_text INTO description.
  archive_documents = VALUE #( ( content     = documents[ 1 ]-content
                                 description = description
                                 file_name   = |Rechnung_{ invoice_number_text }.pdf| ) ).

  " Erst zusammenfuehren, dann ablegen: Scheitert der Merge, ist noch
  " nichts im Content-Repository gespeichert.
  CASE lines( documents ).
    WHEN 1.
      " Keine Anhaenge
    WHEN 2.
      attachments_pdf = documents[ 2 ]-content.
    WHEN OTHERS.
      TRY.
          DATA(merger) = NEW cl_rspo_pdf_merge( ).
          LOOP AT documents FROM 2 REFERENCE INTO DATA(document).
            merger->add_document( document->content ).
          ENDLOOP.

          merger->merge_documents( IMPORTING merged_document = attachments_pdf
                                             rc              = merge_result ).
        CATCH cx_rspo_pdf_merge INTO DATA(merge_error).
          " Ohne CATCH gaebe es einen Kurzdump statt eines lesbaren SM58-Eintrags
          MESSAGE merge_error TYPE 'E'.
      ENDTRY.

      IF merge_result <> 0 OR attachments_pdf IS INITIAL.
        merger->get_err_doc_index( IMPORTING index = error_index ).
        " Index des Mergers zaehlt ab dem ersten Anhang, gemeldet wird die
        " Zeile in DOCUMENTS. Objekt-ID zuletzt: sie ist bis zu 50 Zeichen
        " lang und wuerde den SM58-Statustext sonst abschneiden.
        error_index = error_index + 1.
        DATA(document_count) = lines( documents ).
        MESSAGE e014(zbc_mail_nast_invo) WITH error_index document_count merge_result object_id.
      ENDIF.
  ENDCASE.

  IF attachments_pdf IS NOT INITIAL.
    MESSAGE i016(zbc_mail_nast_invo) WITH invoice_number_text INTO description.
    INSERT VALUE #( content     = attachments_pdf
                    description = description
                    file_name   = |Anlagen_{ invoice_number_text }.pdf| ) INTO TABLE archive_documents.
  ENDIF.

  LOOP AT archive_documents REFERENCE INTO DATA(archive_document).
    " Fuer die Langzeitarchivierung nach PDF/A-3b konvertieren. Schlaegt das
    " fehl, wird das Original abgelegt: Die Ablage ist wichtiger als das Format.
    TRY.
        DATA(pdfa_content) = NEW cl_fp_conv_pdfa( )->run_convert_pdfa(
                                 iv_pdf     = archive_document->content
                                 iv_pdfnorm = if_fp_pdf_norm=>pdf_a3b ).
        IF pdfa_content IS NOT INITIAL.
          archive_document->content = pdfa_content.
        ENDIF.
      CATCH cx_fp_conv ##NO_HANDLER.
    ENDTRY.
    CLEAR pdfa_content.

    " Typ von FLENGTH: LIKE SAPB-LENGTH
    DATA(file_length) = CONV sapb-length( xstrlen( archive_document->content ) ).

    CALL FUNCTION 'ARCHIV_CREATE_TABLE'
      EXPORTING  ar_object  = ar_object
                 object_id  = object_id
                 sap_object = sap_object
                 flength    = file_length
                 doc_type   = 'PDF'
                 document   = archive_document->content
                 filename   = archive_document->file_name
                 descr      = archive_document->description
      EXCEPTIONS OTHERS     = 1.

    IF sy-subrc <> 0.
      " Bereits geschriebene Verknuepfungen dieser LUW werden zurueckgerollt
      MESSAGE e010(zbc_mail_nast_invo) WITH object_id ar_object.
    ENDIF.
  ENDLOOP.
ENDFUNCTION.
