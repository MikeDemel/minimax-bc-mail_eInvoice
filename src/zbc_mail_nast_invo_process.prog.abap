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
REPORT zbc_mail_nast_invo_process.

" Werden von der Nachrichtensteuerung gefuellt, wenn sie hier deklariert sind
TABLES: nast,        " Nachrichtenstatus
        tnapr,       " Verarbeitungsprogramm/Formular aus NACE
        toa_dara.    " ArchiveLink-Index (SAP_OBJECT, AR_OBJECT aus NACE > Ablagesystem)


CLASS lcl_invoice_mail DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES: BEGIN OF processing_result,
             invoice_number TYPE vbeln_vf,
             sent           TYPE abap_bool,
             total_size     TYPE i,
           END OF processing_result.

    METHODS constructor
      IMPORTING message        TYPE nast
                output_program TYPE tnapr
                archive_index  TYPE toa_dara.

    METHODS process
      RETURNING VALUE(result) TYPE processing_result
      RAISING   zcx_sm_sta_send_mail
                zcx_sm_sta_exception.

  PRIVATE SECTION.
    TYPES: BEGIN OF invoice_header,
             vbeln TYPE vbeln_vf,
             vkorg TYPE vkorg,
           END OF invoice_header.

    CONSTANTS:
      " Eigene Dokumentart (OAC2, Dokumentklasse PDF, OAC3 mit VBRK verknuepft)
      attachment_doc_type      TYPE saeobjart VALUE 'ZSDINVATT',
      " Fallback, falls in NACE > Ablagesystem keine Dokumentart gepflegt ist
      default_invoice_doc_type TYPE saeobjart VALUE 'SDOINVOICE',
      default_sap_object       TYPE saeanwdid VALUE 'VBRK',
      " Rohgroesse; die MIME-Mail ist durch Base64 ca. 37 % groesser
      max_size_in_bytes        TYPE i VALUE 10485760,
      body_text_prefix         TYPE string VALUE `ZBC_MAIL_NAST_INVO_BODY`,
      signature_text_prefix    TYPE string VALUE `ZBC_MAIL_NAST_INVO_SIGN`.

    CONSTANTS:
      BEGIN OF archive_mode,
        print_only   TYPE nast-tdarmod VALUE '1',
        archive_only TYPE nast-tdarmod VALUE '2',
        both         TYPE nast-tdarmod VALUE '3',
      END OF archive_mode.

    DATA message        TYPE nast.
    DATA output_program TYPE tnapr.
    DATA archive_index  TYPE toa_dara.

    METHODS get_invoice_header
      RETURNING VALUE(result) TYPE invoice_header
      RAISING   zcx_sm_sta_send_mail.

    METHODS get_documents
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE zcl_bc_mail_nast_invo_mail=>attachment_list
      RAISING   zcx_sm_sta_send_mail.

    METHODS get_invoice_pdf
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE fpcontent
      RAISING   zcx_sm_sta_send_mail.

    METHODS get_attachments
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE zcl_bc_mail_nast_invo_mail=>attachment_list.

    METHODS get_recipient_address
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE ad_smtpadr.

    METHODS get_sender_address
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE ad_smtpadr.

    METHODS build_mail_settings
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE zcl_bc_mail_nast_invo_mail=>mail_config.

    METHODS build_archive_settings
      IMPORTING invoice       TYPE invoice_header
      RETURNING VALUE(result) TYPE zcl_bc_mail_nast_invo_mail=>archive_config.

ENDCLASS.


CLASS lcl_nast_protocol DEFINITION FINAL.
  PUBLIC SECTION.
    "! Uebernimmt die aktuelle Systemnachricht (SY-MSG*) ins NAST-Protokoll
    CLASS-METHODS add_system_message.
ENDCLASS.


*&---------------------------------------------------------------------*
*& Einstieg aus der Nachrichtensteuerung (NACE: FORM-Routine ENTRY)
*&---------------------------------------------------------------------*
FORM entry USING return_code LIKE sy-subrc
                 us_screen   TYPE c.

  return_code = 0.

  IF us_screen = abap_true.
    " Bildschirmausgabe (z. B. Vorschau in VF03): kein Versand
    MESSAGE s012(zbc_mail_nast_invo) INTO DATA(preview_text) ##NEEDED.
    lcl_nast_protocol=>add_system_message( ).
    RETURN.
  ENDIF.

  TRY.
      DATA(result) = NEW lcl_invoice_mail( message        = nast
                                           output_program = tnapr
                                           archive_index  = toa_dara )->process( ).

      IF result-sent = abap_true.
        MESSAGE s011(zbc_mail_nast_invo) WITH result-invoice_number result-total_size INTO DATA(success_text) ##NEEDED.
      ELSE.
        MESSAGE s013(zbc_mail_nast_invo) WITH result-invoice_number INTO DATA(archive_text) ##NEEDED.
      ENDIF.
      lcl_nast_protocol=>add_system_message( ).

    CATCH cx_root INTO DATA(error).
      " Bei Versandzeitpunkt 4 (Verbuchung) darf nichts aus der Routine
      " herauslaufen, sonst bricht die Verbuchung der Faktura ab.
      MESSAGE error TYPE 'E' INTO DATA(error_text) ##NEEDED.
      lcl_nast_protocol=>add_system_message( ).

      " Ursache aus der Exception-Kette zusaetzlich protokollieren
      DATA(previous_error) = error->previous.
      IF previous_error IS BOUND.
        MESSAGE previous_error TYPE 'E' INTO DATA(previous_text) ##NEEDED.
        lcl_nast_protocol=>add_system_message( ).
      ENDIF.

      return_code = 1.
  ENDTRY.
ENDFORM.


CLASS lcl_nast_protocol IMPLEMENTATION.

  METHOD add_system_message.
    CALL FUNCTION 'NAST_PROTOCOL_UPDATE'
      EXPORTING  msg_arbgb = sy-msgid
                 msg_nr    = sy-msgno
                 msg_ty    = sy-msgty
                 msg_v1    = sy-msgv1
                 msg_v2    = sy-msgv2
                 msg_v3    = sy-msgv3
                 msg_v4    = sy-msgv4
      EXCEPTIONS OTHERS    = 1.
    " SY-SUBRC bewusst nicht ausgewertet: ein nicht schreibbares Protokoll
    " darf die Verarbeitung nicht abbrechen.
  ENDMETHOD.

ENDCLASS.


CLASS lcl_invoice_mail IMPLEMENTATION.

  METHOD constructor.
    me->message        = message.
    me->output_program = output_program.
    me->archive_index  = archive_index.
  ENDMETHOD.


  METHOD process.
    DATA(invoice)          = get_invoice_header( ).
    DATA(documents)        = get_documents( invoice ).
    DATA(archive_settings) = COND zcl_bc_mail_nast_invo_mail=>archive_config( WHEN message-tdarmod = archive_mode-archive_only
                                                                                   OR message-tdarmod = archive_mode-both
                                                                                 THEN build_archive_settings( invoice ) ).

    result-invoice_number = invoice-vbeln.
    result-total_size     = zcl_bc_mail_nast_invo_mail=>calculate_total_size( documents ).

    IF message-tdarmod = archive_mode-archive_only.
      NEW zcl_bc_mail_nast_invo_mail(
          mail_settings    = VALUE #( sales_organization = invoice-vkorg )
          archive_settings = archive_settings
        )->archive_invoice( invoice_number = invoice-vbeln
                            documents      = documents ).
      RETURN.
    ENDIF.

    " Pro E-Mail immer eine neue Instanz (MI_BODY der Basisklasse wird nicht geleert)
    NEW zcl_bc_mail_nast_invo_mail(
        mail_settings    = build_mail_settings( invoice )
        archive_settings = archive_settings
      )->send_invoice( invoice_number = invoice-vbeln
                       documents      = documents ).

    result-sent = abap_true.
  ENDMETHOD.


  METHOD get_invoice_header.
    " Bei Zeitpunkt 4 sieht die Verbuchung ihre eigenen, noch nicht
    " committeten Saetze, VBRK ist also bereits lesbar.
    DATA(invoice_number) = CONV vbeln_vf( message-objky(10) ).

    SELECT SINGLE FROM vbrk
      FIELDS vbeln, vkorg
      WHERE vbeln = @invoice_number
      INTO @result.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
        EXPORTING textid = zcx_sm_sta_send_mail=>zcx_error.
    ENDIF.
  ENDMETHOD.


  METHOD get_documents.
    " Konvention: Zeile 1 = Rechnung, ab Zeile 2 = Anhaenge
    result = VALUE #( ( document       = get_invoice_pdf( invoice )
                        document_type  = 'application/pdf'
                        document_title = |{ 'Rechnung'(001) } { invoice-vbeln ALPHA = OUT }| ) ).
    INSERT LINES OF get_attachments( invoice ) INTO TABLE result.
  ENDMETHOD.


  METHOD get_invoice_pdf.
    " TODO: Eure bestehende PDF-Erzeugung einbinden (Adobe-Formular mit GETPDF).
    " Der Formularname steht in OUTPUT_PROGRAM-SFORM (NACE: PDF/SmartForm-Formular),
    " die Sprache in MESSAGE-SPRAS.
    "
    "   result = zcl_..._invoice_pdf=>create( invoice_number = invoice-vbeln
    "                                         form_name      = output_program-sform
    "                                         language       = message-spras ).
    "
    " Wichtig fuer Zeitpunkt 4: keine Vorschau, kein Druckdialog
    " (FP_JOB_OPEN: outputparams-nodialog = abap_true, getpdf = abap_true).
    IF result IS INITIAL.
      RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
        EXPORTING textid = zcx_sm_sta_send_mail=>zcx_error.
    ENDIF.
  ENDMETHOD.


  METHOD get_attachments.
    " TODO: Eure bestehende Ermittlung der Anhaenge (Struktur mit DOCUMENT und
    " Include ZSTA_BO_DIR_DOCS) einbinden. Es werden nur PDFs akzeptiert.
    CLEAR result.
  ENDMETHOD.


  METHOD get_recipient_address.
    " Standard-E-Mail-Adresse des Nachrichtenpartners (NACE: Partnerrolle, z. B. RE)
    SELECT SINGLE FROM vbpa
      INNER JOIN adr6 ON adr6~addrnumber = vbpa~adrnr
      FIELDS adr6~smtp_addr
      WHERE vbpa~vbeln      = @invoice-vbeln
        AND vbpa~posnr      = '000000'
        AND vbpa~parvw      = @message-parvw
        AND adr6~persnumber = @space
        AND adr6~flgdefault = @abap_true
      INTO @result.
  ENDMETHOD.


  METHOD get_sender_address.
    " E-Mail-Adresse aus der Adresse der Verkaufsorganisation (OVX5).
    " Ist keine gepflegt, verwendet die Basisklasse den SAP-Benutzer als Absender.
    SELECT SINGLE FROM tvko
      INNER JOIN adr6 ON adr6~addrnumber = tvko~adrnr
      FIELDS adr6~smtp_addr
      WHERE tvko~vkorg      = @invoice-vkorg
        AND adr6~persnumber = @space
        AND adr6~flgdefault = @abap_true
      INTO @result.
  ENDMETHOD.


  METHOD build_mail_settings.
    result = VALUE #( sender_address      = get_sender_address( invoice )
                      recipient_address   = get_recipient_address( invoice )
                      body_text_name      = |{ body_text_prefix }_{ invoice-vkorg }|
                      signature_text_name = |{ signature_text_prefix }_{ invoice-vkorg }|
                      sales_organization  = invoice-vkorg
                      max_size_in_bytes   = max_size_in_bytes ).
  ENDMETHOD.


  METHOD build_archive_settings.
    " SAP_OBJECT und AR_OBJECT kommen aus NACE > Ablagesystem (via TOA_DARA)
    result = VALUE #(
        active              = abap_true
        sap_object          = COND #( WHEN archive_index-sap_object IS NOT INITIAL
                                      THEN archive_index-sap_object
                                      ELSE default_sap_object )
        object_id           = CONV #( invoice-vbeln )
        invoice_doc_type    = COND #( WHEN archive_index-ar_object IS NOT INITIAL
                                      THEN archive_index-ar_object
                                      ELSE default_invoice_doc_type )
        attachment_doc_type = attachment_doc_type ).
  ENDMETHOD.

ENDCLASS.
