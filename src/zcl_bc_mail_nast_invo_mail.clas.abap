class zcl_bc_mail_nast_invo_mail definition
  public
  inheriting from zcl_sm_sta_send_mail
  final
  create public.

  public section.
    types: begin of attachment,
             document type fpcontent.
             include type zsta_bo_dir_docs.
           types: end of attachment.
    types attachment_list type standard table of attachment with empty key.

    types: begin of mail_config,
             sender_address      type ad_smtpadr,
             recipient_address   type ad_smtpadr,
             body_text_name      type tdobname,
             signature_text_name type tdobname,
             sales_organization  type vkorg,
             max_size_in_bytes   type i,              " 0 = keine Pruefung
           end of mail_config.

    types: begin of archive_config,
             active              type abap_bool,
             sap_object          type saeanwdid,      " z. B. VBRK
             object_id           type saeobjid,       " Fakturanummer
             doc_type            type saeobjart,      " Dokumentart des zusammengefuehrten PDF
           end of archive_config.

    constants placeholder_invoice_number type typ_placeholder_d value '&INVOICE_NUMBER&'.

    "! Rohgroesse aller Dokumente der zuletzt versendeten E-Mail in Byte
    data total_size type i read-only.

    methods constructor
      importing mail_settings    type mail_config
                archive_settings type archive_config optional
                archiver         type ref to zif_bc_mail_nast_invo_archive optional.

    "! Versendet die Rechnung und registriert danach die Ablage.
    "! Zeile 1 = Rechnungs-PDF, ab Zeile 2 = Anhaenge. Nur PDF.
    methods send_invoice
      importing invoice_number type vbeln_vf
                documents      type attachment_list
      raising   zcx_sm_sta_send_mail.

    "! Nur ablegen, kein Versand (Archivierungsmodus 2)
    methods archive_invoice
      importing invoice_number type vbeln_vf
                documents      type attachment_list
      raising   zcx_sm_sta_send_mail.

    "! Rohgroesse in Byte; die MIME-Mail ist durch Base64 ca. 37 % groesser
    class-methods calculate_total_size
      importing documents     type attachment_list
      returning value(result) type i.

  protected section.
    methods add_copy_to                redefinition.
    methods attach_documents           redefinition.
    methods before_send                redefinition.
    methods get_data                   redefinition.
    methods get_recipient              redefinition.
    methods get_recipient_address      redefinition.
    methods get_sender                 redefinition.
    methods get_textname_for_body      redefinition.
    methods get_textname_for_signature redefinition.

    methods set_placeholders           redefinition.
    methods set_recipient_address      redefinition.


  private section.
    constants pdf_signature type x length 5 value '255044462D'. " %PDF-

    data mail_settings    type mail_config.
    data archive_settings type archive_config.
    data archiver         type ref to zif_bc_mail_nast_invo_archive.
    data invoice_number   type vbeln_vf.
    data documents        type attachment_list.

    methods add_attachment
      importing content   type xstring
                file_name type string
      raising   cx_document_bcs.

    methods archive_documents.

    methods check_documents
      raising zcx_sm_sta_send_mail.

    methods check_size
      raising zcx_sm_sta_send_mail.

    class-methods get_file_name
      importing attachment    type attachment
      returning value(result) type string.

    class-methods is_valid_pdf
      importing attachment    type attachment
      returning value(result) type abap_bool.

endclass.



class zcl_bc_mail_nast_invo_mail implementation.

  method constructor.
    super->constructor( ).
    me->mail_settings    = mail_settings.
    me->archive_settings = archive_settings.
    me->archiver = cond #( when archiver is bound
                           then archiver
                           else new zcl_bc_mail_nast_invo_archive( ) ).
    " Wird von BUILD_HTML_BODY fuer die Signaturlogik benoetigt
    sales_org_number = mail_settings-sales_organization.
  endmethod.


  method send_invoice.
    me->invoice_number = invoice_number.
    me->documents      = documents.
    total_size = calculate_total_size( documents ).

    try.
        send_mail( ).
      catch zcx_sm_sta_exception into data(lox_sm_sta_exception).
        raise exception type zcx_sm_sta_send_mail
          exporting
            mi_messages = lox_sm_sta_exception->mi_messages.
    endtry.

    " Erst nach erfolgreichem Versand registrieren: schlaegt der Versand fehl,
    " wird nichts abgelegt und eine Wiederholung erzeugt keine Dubletten.
    archive_documents( ).
  endmethod.


  method archive_invoice.
    me->invoice_number = invoice_number.
    me->documents      = documents.
    total_size = calculate_total_size( documents ).

    check_documents( ).
    archive_documents( ).
  endmethod.


  method calculate_total_size.
    result = reduce i( init sum = 0
                       for document in documents
                       next sum = sum + xstrlen( document-document ) ).
  endmethod.


  method get_data ##NEEDED.
    " Alle Daten kommen ueber SEND_INVOICE
  endmethod.


  method add_copy_to ##NEEDED.
    " Keine Kopieempfaenger vorgesehen
  endmethod.


  method get_sender.
    if mail_settings-sender_address is initial.
      ro_sender = super->get_sender( ).
    else.
      ro_sender = cl_cam_address_bcs=>create_internet_address( mail_settings-sender_address ).
    endif.
  endmethod.


  method get_recipient.
    ro_recipient = cl_cam_address_bcs=>create_internet_address( get_recipient_address( ) ).
  endmethod.


  method get_recipient_address.
    if mail_settings-recipient_address is initial.
      " Empfehlung: eigene Text-ID "keine Empfaengeradresse"
      raise exception type zcx_sm_sta_send_mail
        exporting
          textid = zcx_sm_sta_send_mail=>zcx_error.
    endif.
    rd_email_string = mail_settings-recipient_address.
  endmethod.


  method set_recipient_address.
    mail_settings-recipient_address = id_email.
  endmethod.


  method get_textname_for_body.
    rd_itf_textname = mail_settings-body_text_name.
  endmethod.


  method get_textname_for_signature.
    rd_itf_textname = mail_settings-signature_text_name.
  endmethod.


  method set_placeholders.
    ci_placeholder = value #( base ci_placeholder
                              ( placeholder = placeholder_invoice_number
                                value       = |{ invoice_number alpha = out }| ) ).
  endmethod.


  method before_send.
    check_documents( ).
    check_size( ).
  endmethod.


  method attach_documents.
    " II_PDF_DATA der Basisklasse wird bewusst nicht verwendet
    loop at documents reference into data(document).
      add_attachment( content   = document->document
                      file_name = get_file_name( document->* ) ).
    endloop.
  endmethod.


  method add_attachment.
    mo_document->add_attachment(
        i_attachment_type    = 'PDF'
        i_attachment_subject = conv so_obj_des( file_name )
        i_attachment_size    = conv so_obj_len( xstrlen( content ) )
        i_att_content_hex    = cl_document_bcs=>xstring_to_solix( content )
        i_attachment_header  = value soli_tab( ( |{ cl_bcs_objhead=>gc_filename }={ file_name }| ) ) ).
  endmethod.


  method check_documents.
    if documents is initial.
      raise exception type zcx_sm_sta_send_mail
        exporting
          textid = zcx_sm_sta_send_mail=>zcx_error.
    endif.

    loop at documents reference into data(document).
      if is_valid_pdf( document->* ) = abap_false.
        " Empfehlung: eigene Text-ID "kein gueltiges PDF"
        raise exception type zcx_sm_sta_send_mail
          exporting
            textid = zcx_sm_sta_send_mail=>zcx_error.
      endif.
    endloop.
  endmethod.


  method is_valid_pdf.
    if to_lower( condense( attachment-document_type ) ) <> `application/pdf`.
      return.
    endif.
    if xstrlen( attachment-document ) < 5.
      return.
    endif.
    result = xsdbool( attachment-document(5) = pdf_signature ).
  endmethod.


  method check_size.
    if mail_settings-max_size_in_bytes > 0 and total_size > mail_settings-max_size_in_bytes.
      " Empfehlung: eigene Text-ID "E-Mail zu gross"
      raise exception type zcx_sm_sta_send_mail
        exporting
          textid = zcx_sm_sta_send_mail=>zcx_error.
    endif.
  endmethod.


  method get_file_name.
    result = condense( attachment-document_title ).
    if result is initial.
      result = |{ 'Dokument'(001) }_{ attachment-document_nr alpha = out }|.
    endif.
    if not matches( val = to_lower( result ) regex = `.*\.pdf` ).
      result = |{ result }.pdf|.
    endif.
  endmethod.


  method archive_documents.
    if archive_settings-active = abap_false.
      return.
    endif.

    archiver->archive(
        sap_object = archive_settings-sap_object
        object_id  = archive_settings-object_id
        ar_object  = archive_settings-doc_type
        documents  = value #( for document in documents ( content = document-document ) ) ).
  endmethod.

endclass.
