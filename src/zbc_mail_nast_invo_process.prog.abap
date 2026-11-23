*&---------------------------------------------------------------------*
*& Report ZBC_MAIL_NAST_INVO_PROCESS
*&---------------------------------------------------------------------*
*& Verarbeitungsprogramm fuer Nachrichtenart ZEIM (Applikation V3)
*& NACE > Verarbeitungsroutinen:
*&   Medium 5 (Externe Sendung), Programm ZBC_MAIL_NAST_INVO_PROCESS,
*&   FORM-Routine ENTRY, PDF/SmartForm-Formular = euer Adobe-Formular
*&
*& Laeuft bei Versandzeitpunkt 1/3 unter RSNAST00/VF31 und bei
*& Versandzeitpunkt 4 in der Verbuchung der Faktura. Deshalb:
*&   - kein COMMIT, kein Dialog, keine Exception aus FORM ENTRY heraus
*&   - Ablage per tRFC (ZCL_BC_MAIL_NAST_INVO_ARCHIVE)
*&---------------------------------------------------------------------*
report zbc_mail_nast_invo_process.

" Werden von der Nachrichtensteuerung gefuellt, wenn sie hier deklariert sind
tables: nast,        " Nachrichtenstatus
        tnapr,       " Verarbeitungsprogramm/Formular aus NACE
        toa_dara.    " ArchiveLink-Index (SAP_OBJECT, AR_OBJECT aus NACE > Ablagesystem)


class lcl_invoice_mail definition final.
  public section.
    types: begin of processing_result,
             invoice_number type vbeln_vf,
             sent           type abap_bool,
             total_size     type i,
           end of processing_result.

    methods constructor
      importing message        type nast
                output_program type tnapr
                archive_index  type toa_dara.

    methods process
      returning value(result) type processing_result
      raising   zcx_sm_sta_send_mail.

  private section.
    types: begin of invoice_header,
             vbeln type vbeln_vf,
             vkorg type vkorg,
           end of invoice_header.

    constants:
      " Fallback, falls in NACE > Ablagesystem keine Dokumentart gepflegt ist
      " (wie im bisherigen Druckprozess)
      default_doc_type         type saeobjart value 'ZEDI_INVOI',
      default_sap_object       type saeanwdid value 'VBRK',
      " Rohgroesse; die MIME-Mail ist durch Base64 ca. 37 % groesser
      max_size_in_bytes        type i value 10485760,
      body_text_prefix         type string value `ZBC_MAIL_NAST_INVO_BODY_`,
      signature_text_prefix    type string value `ZCA_`,
      signature_text_postfix    type string value `_SIGNATURE`.

    constants:
      begin of archive_mode,
        print_only   type nast-tdarmod value '1',
        archive_only type nast-tdarmod value '2',
        both         type nast-tdarmod value '3',
      end of archive_mode.

    data message        type nast.
    data output_program type tnapr.
    data archive_index  type toa_dara.
    data invoice_number type vbeln_vf.

    methods get_documents
      returning value(result) type zcl_bc_mail_nast_invo_mail=>attachment_list
      raising   zcx_sm_sta_send_mail.

    methods get_invoice_pdf
      returning value(result) type zcl_bc_mail_nast_invo_mail=>attachment_list
      raising   zcx_sm_sta_send_mail.

    methods get_attachments
      returning value(result) type zcl_bc_mail_nast_invo_mail=>attachment_list
      raising   zcx_sm_sta_send_mail.

    methods get_recipient_address
      returning value(result) type ad_smtpadr
      raising   zcx_sm_sta_send_mail.

    methods get_sender_address
      returning value(result) type AD_SMTPADR.

    methods build_mail_settings
      returning value(result) type zcl_bc_mail_nast_invo_mail=>mail_config
      raising   zcx_sm_sta_send_mail.

    methods build_archive_settings
      returning value(result) type zcl_bc_mail_nast_invo_mail=>archive_config.

    methods build_object_id
      returning value(result) type saeobjid.

endclass.


class lcl_nast_protocol definition final.
  public section.
    class-methods add_logger importing logger type ref to zif_sm_sta_msg_handler.
endclass.


*&---------------------------------------------------------------------*
*& Einstieg aus der Nachrichtensteuerung (NACE: FORM-Routine ENTRY)
*&---------------------------------------------------------------------*
form entry using return_code like sy-subrc
                 us_screen   type c.

  return_code = 0.

  data(msg_handler) = zcl_sm_sta_msg_handler_factory=>get_instance( ).
  if us_screen = abap_true.
    msg_handler->add_info_message( id_id = 'ZBC_MAIL_NAST_INVO' id_number = '012' ).
    if 1 = 2. message s012(zbc_mail_nast_invo). endif.
    lcl_nast_protocol=>add_logger( msg_handler ).
    return.
  endif.

  try.
      data(result) = new lcl_invoice_mail( message        = nast
                                           output_program = tnapr
                                           archive_index  = toa_dara )->process( ).

      if result-sent = abap_true.
        msg_handler->add_info_message( id_id = 'ZBC_MAIL_NAST_INVO' id_number = '011' id_v1 = result-invoice_number id_v2_i = result-total_size ).
        if 1 = 2. message s011(zbc_mail_nast_invo) with space space. endif.
      else.
        msg_handler->add_info_message( id_id = 'ZBC_MAIL_NAST_INVO' id_number = '013' id_v1 = result-invoice_number  ).
        if 1 = 2. message s013(zbc_mail_nast_invo) with space . endif.
      endif.
      lcl_nast_protocol=>add_logger( msg_handler ).

    catch cx_root into data(lox_root).
      " Bei Versandzeitpunkt 4 (Verbuchung) darf nichts aus der Routine
      " herauslaufen, sonst bricht die Verbuchung der Faktura ab.
      msg_handler->add_exception_class( id_with_ex_name = abap_false io_ex = lox_root ).

      " Ursache aus der Exception-Kette zusaetzlich protokollieren
      data(previous_error) = lox_root->previous.
      if previous_error is bound.
        msg_handler->add_exception_class( id_with_ex_name = abap_false io_ex = previous_error ).
      endif.
      lcl_nast_protocol=>add_logger( msg_handler ).
      return_code = 1.
  endtry.
endform.


class lcl_nast_protocol implementation.

  method add_logger.
    loop at logger->get_bapiret2( ) reference into data(bapiret2).
      call function 'NAST_PROTOCOL_UPDATE'
        exporting
          msg_arbgb = bapiret2->id
          msg_nr    = bapiret2->number
          msg_ty    = bapiret2->type
          msg_v1    = bapiret2->message_v1
          msg_v2    = bapiret2->message_v2
          msg_v3    = bapiret2->message_v3
          msg_v4    = bapiret2->message_v4
        exceptions
          others    = 1.
      " SY-SUBRC bewusst nicht ausgewertet: ein nicht schreibbares Protokoll
      " darf die Verarbeitung nicht abbrechen.
    endloop.
  endmethod.

endclass.


class lcl_invoice_mail implementation.

  method constructor.
    me->message        = message.
    me->output_program = output_program.
    me->archive_index  = archive_index.
    me->invoice_number = conv vbeln_vf( message-objky ).
  endmethod.


  method process.
    data(documents) = get_documents(  ).

    result-invoice_number = me->invoice_number.
    result-total_size     = zcl_bc_mail_nast_invo_mail=>calculate_total_size( documents ).

    data(mail) = new zcl_bc_mail_nast_invo_mail( mail_settings    = build_mail_settings(  )
                                                 archive_settings = build_archive_settings(  ) ).

    if message-tdarmod = archive_mode-archive_only.
      mail->archive_invoice( invoice_number = me->invoice_number
                             documents      = documents ).
      return.
    endif.

    mail->send_invoice( invoice_number = me->invoice_number
                        documents      = documents ).
    result-sent = abap_true.
  endmethod.
  method get_documents.
    " Konvention: Zeile 1 = Rechnung, ab Zeile 2 = Anhaenge
    insert lines of get_invoice_pdf(  ) into table result.
    insert lines of get_attachments(  ) into table result.
  endmethod.


  method get_invoice_pdf.
    data(nast) = value nast( objky = invoice_number
                         kappl = zif_sta_sd_inv_nast=>co_kappl_invoice
                         parnr = message-parnr
                         kschl = zif_sta_sd_inv_nast=>co_msg_type_invoice_mail
                         ldest  = zif_sta_sd_inv_form=>co_ldest_locl ).

    select single from tnapr
       fields *
         where kschl = @nast-kschl
         and   nacha = @zif_sta_sd_inv_nast=>co_trans_medium_print_output
         and   kappl = @nast-kappl
         into @data(tnapr).

    data(attachment_pdf) = value fpcontent( ).
    zcl_idoc_invo_joubini_mode_fac=>get_instance(  invoice_number )->set_processing_mode(  zif_idoc_invo_joubini_mode=>processing_mode_attachm_only ).
    call function '/IX2/EINV_GET_PDF'
      exporting
        is_nast  = nast
        is_tnapr = tnapr
      importing
        ef_pdf   = attachment_pdf.

    if attachment_pdf is initial.
      data(msg_handler) = zcl_sm_sta_msg_handler_factory=>get_instance( ).
      msg_handler->add_error_message( id_id = 'ZBC01' id_number = 009 id_v1 = me->invoice_number ).
      raise exception type zcx_sm_sta_send_mail exporting mi_messages = msg_handler->get_messages( ).
      if 1 = 2. message e009(zbc01) with space. endif.
    endif.

    result = value #( ( document       = attachment_pdf
                        document_type  = 'application/pdf'
                        document_title = |{ 'Rechnung'(001) } { me->invoice_number alpha = out }| ) ).

  endmethod.


  method get_attachments.

    try.
        data(attachments) = zcl_idoc_invo_joubini_atta_fac=>get_instance( me->invoice_number )->get_mail_attachments(  ).

      catch /ix2/cx_einvoice_exception into data(lox_einvoice_exception).
        data(messages) = value bapiret2_t( (  type = lox_einvoice_exception->gs_message-msgty
                                              id = lox_einvoice_exception->gs_message-msgid
                                              number = lox_einvoice_exception->gs_message-msgno
                                              message_v1 = lox_einvoice_exception->gs_message-msgv1
                                              message_v2 = lox_einvoice_exception->gs_message-msgv2
                                              message_v3 = lox_einvoice_exception->gs_message-msgv3
                                              message_v4  = lox_einvoice_exception->gs_message-msgv4 ) ) .
        raise exception type zcx_sm_sta_send_mail exporting mi_messages = messages.
    endtry.

    loop at attachments reference into data(attachment).
      insert value #( document       = attachment->content
                      document_type  = 'application/pdf'
                      document_title = attachment->title ) into table result.
    endloop.

  endmethod.


  method get_recipient_address.

    select single
     from zbc_idoc_jou_acr
     fields email
      where kunnr = @me->message-parnr
      into @data(email_recipient).

    if sy-subrc <> 0 or email_recipient is initial.
      data(msg_handler) = zcl_sm_sta_msg_handler_factory=>get_instance( ).
      msg_handler->add_error_message( id_id = 'ZBC01' id_number = 015 id_v1 = me->message-parnr ).
      raise exception type zcx_sm_sta_send_mail exporting mi_messages = msg_handler->get_messages( ).
      if 1 = 2. message e015(zbc01) with space. endif.
    endif.
    result = email_recipient.

  endmethod.


  method get_sender_address.
    " E-Mail-Adresse aus der Adresse der Verkaufsorganisation (OVX5).
    " Ist keine gepflegt, verwendet die Basisklasse den SAP-Benutzer als Absender.
   select single
     from vbrk
     inner join tvko on tvko~vkorg = vbrk~vkorg
      inner join adr6 on adr6~addrnumber = tvko~adrnr
      fields adr6~smtp_addr
      where vbrk~vbeln      = @me->invoice_number
        and adr6~persnumber = @space
        and adr6~flgdefault = @abap_true
      into @result.
  endmethod.


  method build_mail_settings.

    select single
     from vbrk
     fields vkorg, bukrs
     where vbeln = @me->invoice_number
     into @data(organization).

    result = value #( sender_address      = get_sender_address(   )
                      recipient_address   = get_recipient_address(  )
                      body_text_name      = |{ body_text_prefix }{ organization-vkorg }|
                      signature_text_name = |{ signature_text_prefix }{ organization-bukrs }{ signature_text_postfix }|
                      sales_organization  = organization-vkorg
                      max_size_in_bytes   = max_size_in_bytes ).
  endmethod.


  method build_archive_settings.
    " SAP_OBJECT, OBJECT_ID und AR_OBJECT kommen aus der Nachrichtensteuerung (via TOA_DARA)
    result = value #( active              = xsdbool( message-tdarmod = archive_mode-archive_only   or message-tdarmod = archive_mode-both )
                          sap_object          = archive_index-sap_object
                          object_id           = archive_index-object_id
                          doc_type            = archive_index-ar_object ).

    " Fallbacks, falls die Nachrichtensteuerung TOA_DARA nicht gefuellt hat
    if result-sap_object is initial.
      result-sap_object = default_sap_object.
    endif.
    if result-object_id is initial.
      result-object_id = build_object_id( ).
    endif.
    if result-doc_type is initial.
      result-doc_type = default_doc_type.
    endif.
  endmethod.


  method build_object_id.
    " Standardaufbau: OBJKY (30 Zeichen, mit Leerzeichen) + OPTARCNR.
    " Ohne RESPECTING BLANKS fielen die Leerzeichen am Ende von OBJKY weg.
    concatenate message-objky message-optarcnr into result respecting blanks.
  endmethod.

endclass.
