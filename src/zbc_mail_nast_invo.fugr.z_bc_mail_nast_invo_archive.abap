FUNCTION z_bc_mail_nast_invo_archive.
*"----------------------------------------------------------------------
*"*"Lokale Schnittstelle:
*"  IMPORTING
*"     VALUE(SAP_OBJECT) TYPE  SAEANWDID
*"     VALUE(OBJECT_ID) TYPE  SAEOBJID
*"     VALUE(AR_OBJECT) TYPE  SAEOBJART
*"     VALUE(DOCUMENTS) TYPE  ZBC_MAIL_NAST_INVO_ARC_DOCS
*"----------------------------------------------------------------------
  " Rechnung und Anhaenge werden zu einem PDF zusammengefuehrt und als ein
  " Dokument abgelegt. Fehler brechen die tRFC-LUW ab: Eintrag in SM58,
  " dort wiederholbar.
  DATA binary_content TYPE STANDARD TABLE OF tbl1024 WITH EMPTY KEY.
  DATA length         TYPE i.
  DATA merged_pdf     TYPE xstring.
  DATA merge_result   TYPE i.
  DATA error_index    TYPE i.

  IF documents IS INITIAL.
    RETURN.
  ENDIF.

  IF lines( documents ) = 1.
    merged_pdf = documents[ 1 ]-content.
  ELSE.
    " Zusammenfuehren ueber ADS (Signatur von CL_RSPO_PDF_MERGE in SE24 gegenpruefen)
    DATA(merger) = NEW cl_rspo_pdf_merge( ).
    LOOP AT documents REFERENCE INTO DATA(document).
      merger->add_document( document->content ).
    ENDLOOP.

    merger->merge_documents( IMPORTING merged_document = merged_pdf
                                       rc              = merge_result ).
    IF merge_result <> 0 OR merged_pdf IS INITIAL.
      merger->get_err_doc_index( IMPORTING index = error_index ).
      MESSAGE e014(zbc_mail_nast_invo) WITH object_id error_index.
    ENDIF.
  ENDIF.

  CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
    EXPORTING buffer        = merged_pdf
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
    MESSAGE e010(zbc_mail_nast_invo) WITH object_id ar_object.
  ENDIF.
ENDFUNCTION.
