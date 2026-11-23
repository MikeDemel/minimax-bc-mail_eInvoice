FUNCTION z_bc_mail_nast_invo_archive.
*"----------------------------------------------------------------------
*"*"Lokale Schnittstelle:
*"  IMPORTING
*"     VALUE(SAP_OBJECT) TYPE  SAEANWDID
*"     VALUE(OBJECT_ID) TYPE  SAEOBJID
*"     VALUE(DOCUMENTS) TYPE  ZBC_MAIL_NAST_INVO_ARC_DOCS
*"----------------------------------------------------------------------
  DATA binary_content TYPE STANDARD TABLE OF tbl1024 WITH EMPTY KEY.
  DATA length         TYPE i.

  LOOP AT documents REFERENCE INTO DATA(document).
    CLEAR: binary_content, length.

    CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
      EXPORTING buffer        = document->content
      IMPORTING output_length = length
      TABLES    binary_tab    = binary_content.

    " Typ von FLENGTH in SE37 gegenpruefen (LIKE SAPB-LENGTH)
    DATA(file_length) = CONV sapb-length( length ).

    CALL FUNCTION 'ARCHIV_CREATE_TABLE'
      EXPORTING  ar_object       = document->ar_object
                 object_id       = object_id
                 sap_object      = sap_object
                 flength         = file_length
                 doc_type        = 'PDF'
      TABLES     binarchivobject = binary_content
      EXCEPTIONS OTHERS          = 1.

    IF sy-subrc <> 0.
      " Bricht die tRFC-LUW ab: Eintrag in SM58, dort wiederholbar.
      " Bereits geschriebene Verknuepfungen dieser LUW werden zurueckgerollt.
      MESSAGE e010(zbc_mail_nast_invo) WITH object_id document->ar_object.
    ENDIF.
  ENDLOOP.
ENDFUNCTION.
