CLASS zcl_bc_mail_nast_invo_mail DEFINITION
  PUBLIC
  INHERITING FROM zcl_sm_sta_send_mail
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF attachment,
             document TYPE fpcontent.
             INCLUDE TYPE zsta_bo_dir_docs.
    TYPES: END OF attachment.
    TYPES attachment_list TYPE STANDARD TABLE OF attachment WITH EMPTY KEY.

    TYPES: BEGIN OF mail_config,
             sender_address      TYPE ad_smtpadr,
             recipient_address   TYPE ad_smtpadr,
             body_text_name      TYPE tdobname,
             signature_text_name TYPE tdobname,
             sales_organization  TYPE vkorg,
             max_size_in_bytes   TYPE i,              " 0 = keine Pruefung
           END OF mail_config.

    TYPES: BEGIN OF archive_config,
             active              TYPE abap_bool,
             sap_object          TYPE saeanwdid,      " z. B. VBRK
             object_id           TYPE saeobjid,       " Fakturanummer
             invoice_doc_type    TYPE saeobjart,      " Dokumentart Zeile 1
             attachment_doc_type TYPE saeobjart,      " Dokumentart ab Zeile 2
           END OF archive_config.

    CONSTANTS placeholder_invoice_number TYPE typ_placeholder_d VALUE '&INVOICE_NUMBER&'.

    "! Rohgroesse aller Dokumente der zuletzt versendeten E-Mail in Byte
    DATA total_size TYPE i READ-ONLY.

    METHODS constructor
      IMPORTING mail_settings    TYPE mail_config
                archive_settings TYPE archive_config OPTIONAL
                archiver         TYPE REF TO zif_bc_mail_nast_invo_archive OPTIONAL.

    "! Versendet die Rechnung und registriert danach die Ablage.
    "! Zeile 1 = Rechnungs-PDF, ab Zeile 2 = Anhaenge. Nur PDF.
    METHODS send_invoice
      IMPORTING invoice_number TYPE vbeln_vf
                documents      TYPE attachment_list
      RAISING   zcx_sm_sta_send_mail
                zcx_sm_sta_exception.

    "! Nur ablegen, kein Versand (Archivierungsmodus 2)
    METHODS archive_invoice
      IMPORTING invoice_number TYPE vbeln_vf
                documents      TYPE attachment_list
      RAISING   zcx_sm_sta_send_mail.

    "! Rohgroesse in Byte; die MIME-Mail ist durch Base64 ca. 37 % groesser
    CLASS-METHODS calculate_total_size
      IMPORTING documents     TYPE attachment_list
      RETURNING VALUE(result) TYPE i.

  PROTECTED SECTION.
    METHODS add_copy_to                REDEFINITION.
    METHODS attach_documents           REDEFINITION.
    METHODS before_send                REDEFINITION.
    METHODS get_data                   REDEFINITION.
    METHODS get_recipient              REDEFINITION.
    METHODS get_recipient_address      REDEFINITION.
    METHODS get_sender                 REDEFINITION.
    METHODS get_textname_for_body      REDEFINITION.
    METHODS get_textname_for_signature REDEFINITION.
    METHODS is_commit_allowed          REDEFINITION.
    METHODS set_placeholders           REDEFINITION.
    METHODS set_recipient_address      REDEFINITION.
    METHODS with_error_screen          REDEFINITION.

  PRIVATE SECTION.
    CONSTANTS pdf_signature TYPE x LENGTH 5 VALUE '255044462D'. " %PDF-

    DATA mail_settings    TYPE mail_config.
    DATA archive_settings TYPE archive_config.
    DATA archiver         TYPE REF TO zif_bc_mail_nast_invo_archive.
    DATA invoice_number   TYPE vbeln_vf.
    DATA documents        TYPE attachment_list.

    METHODS add_attachment
      IMPORTING content   TYPE xstring
                file_name TYPE string
      RAISING   cx_document_bcs.

    METHODS archive_documents.

    METHODS check_documents
      RAISING zcx_sm_sta_send_mail.

    METHODS check_size
      RAISING zcx_sm_sta_send_mail.

    CLASS-METHODS get_file_name
      IMPORTING attachment    TYPE attachment
      RETURNING VALUE(result) TYPE string.

    CLASS-METHODS is_valid_pdf
      IMPORTING attachment    TYPE attachment
      RETURNING VALUE(result) TYPE abap_bool.

ENDCLASS.



CLASS zcl_bc_mail_nast_invo_mail IMPLEMENTATION.

  METHOD constructor.
    super->constructor( ).
    me->mail_settings    = mail_settings.
    me->archive_settings = archive_settings.
    me->archiver = COND #( WHEN archiver IS BOUND
                           THEN archiver
                           ELSE NEW zcl_bc_mail_nast_invo_archive( ) ).
    " Wird von BUILD_HTML_BODY fuer die Signaturlogik benoetigt
    sales_org_number = mail_settings-sales_organization.
  ENDMETHOD.


  METHOD send_invoice.
    me->invoice_number = invoice_number.
    me->documents      = documents.
    total_size = calculate_total_size( documents ).

    send_mail( ).

    " Erst nach erfolgreichem Versand registrieren: schlaegt der Versand fehl,
    " wird nichts abgelegt und eine Wiederholung erzeugt keine Dubletten.
    archive_documents( ).
  ENDMETHOD.


  METHOD archive_invoice.
    me->invoice_number = invoice_number.
    me->documents      = documents.
    total_size = calculate_total_size( documents ).

    check_documents( ).
    archive_documents( ).
  ENDMETHOD.


  METHOD calculate_total_size.
    result = REDUCE i( INIT sum = 0
                       FOR document IN documents
                       NEXT sum = sum + xstrlen( document-document ) ).
  ENDMETHOD.


  METHOD get_data ##NEEDED.
    " Alle Daten kommen ueber SEND_INVOICE
  ENDMETHOD.


  METHOD add_copy_to ##NEEDED.
    " Keine Kopieempfaenger vorgesehen
  ENDMETHOD.


  METHOD get_sender.
    IF mail_settings-sender_address IS INITIAL.
      ro_sender = super->get_sender( ).
    ELSE.
      ro_sender = cl_cam_address_bcs=>create_internet_address( mail_settings-sender_address ).
    ENDIF.
  ENDMETHOD.


  METHOD get_recipient.
    ro_recipient = cl_cam_address_bcs=>create_internet_address( get_recipient_address( ) ).
  ENDMETHOD.


  METHOD get_recipient_address.
    IF mail_settings-recipient_address IS INITIAL.
      " Empfehlung: eigene Text-ID "keine Empfaengeradresse"
      RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
        EXPORTING textid = zcx_sm_sta_send_mail=>zcx_error.
    ENDIF.
    rd_email_string = mail_settings-recipient_address.
  ENDMETHOD.


  METHOD set_recipient_address.
    mail_settings-recipient_address = id_email.
  ENDMETHOD.


  METHOD get_textname_for_body.
    rd_itf_textname = mail_settings-body_text_name.
  ENDMETHOD.


  METHOD get_textname_for_signature.
    rd_itf_textname = mail_settings-signature_text_name.
  ENDMETHOD.


  METHOD set_placeholders.
    ci_placeholder = VALUE #( BASE ci_placeholder
                              ( placeholder = placeholder_invoice_number
                                value       = |{ invoice_number ALPHA = OUT }| ) ).
  ENDMETHOD.


  METHOD is_commit_allowed.
    " Im NAST-Kontext committet RSNAST00/VF31 bzw. die Verbuchung (Zeitpunkt 4)
    result = abap_false.
  ENDMETHOD.


  METHOD with_error_screen.
    " Kein Dialog: Batch (RSNAST00) bzw. Verbuchung (Zeitpunkt 4)
    result = abap_false.
  ENDMETHOD.


  METHOD before_send.
    check_documents( ).
    check_size( ).
  ENDMETHOD.


  METHOD attach_documents.
    " II_PDF_DATA der Basisklasse wird bewusst nicht verwendet
    LOOP AT documents REFERENCE INTO DATA(document).
      add_attachment( content   = document->document
                      file_name = get_file_name( document->* ) ).
    ENDLOOP.
  ENDMETHOD.


  METHOD add_attachment.
    mo_document->add_attachment(
        i_attachment_type    = 'PDF'
        i_attachment_subject = CONV so_obj_des( file_name )
        i_attachment_size    = CONV so_obj_len( xstrlen( content ) )
        i_att_content_hex    = cl_document_bcs=>xstring_to_solix( content )
        i_attachment_header  = VALUE soli_tab( ( |{ cl_bcs_objhead=>gc_filename }={ file_name }| ) ) ).
  ENDMETHOD.


  METHOD check_documents.
    IF documents IS INITIAL.
      RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
        EXPORTING textid = zcx_sm_sta_send_mail=>zcx_error.
    ENDIF.

    LOOP AT documents REFERENCE INTO DATA(document).
      IF is_valid_pdf( document->* ) = abap_false.
        " Empfehlung: eigene Text-ID "kein gueltiges PDF"
        RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
          EXPORTING textid = zcx_sm_sta_send_mail=>zcx_error.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD is_valid_pdf.
    IF to_lower( condense( attachment-document_type ) ) <> `application/pdf`.
      RETURN.
    ENDIF.
    IF xstrlen( attachment-document ) < 5.
      RETURN.
    ENDIF.
    result = xsdbool( attachment-document(5) = pdf_signature ).
  ENDMETHOD.


  METHOD check_size.
    IF mail_settings-max_size_in_bytes > 0 AND total_size > mail_settings-max_size_in_bytes.
      " Empfehlung: eigene Text-ID "E-Mail zu gross"
      RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
        EXPORTING textid = zcx_sm_sta_send_mail=>zcx_error.
    ENDIF.
  ENDMETHOD.


  METHOD get_file_name.
    result = condense( attachment-document_title ).
    IF result IS INITIAL.
      result = |{ 'Dokument'(001) }_{ attachment-document_nr ALPHA = OUT }|.
    ENDIF.
    IF NOT matches( val = to_lower( result ) regex = `.*\.pdf` ).
      result = |{ result }.pdf|.
    ENDIF.
  ENDMETHOD.


  METHOD archive_documents.
    IF archive_settings-active = abap_false.
      RETURN.
    ENDIF.

    archiver->archive(
        sap_object = archive_settings-sap_object
        object_id  = archive_settings-object_id
        documents  = VALUE #( FOR document IN documents INDEX INTO index
                              ( ar_object = COND #( WHEN index = 1
                                                    THEN archive_settings-invoice_doc_type
                                                    ELSE archive_settings-attachment_doc_type )
                                content   = document-document ) ) ).
  ENDMETHOD.

ENDCLASS.
