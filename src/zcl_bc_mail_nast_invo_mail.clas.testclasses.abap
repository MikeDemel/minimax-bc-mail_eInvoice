* Include "Testklassen" von ZCL_BC_MAIL_NAST_INVO_MAIL
*
* Hinweis: Der Konstruktor der Basisklasse ruft
* ZCL_SM_STA_MSG_HANDLER_FACTORY=>GET_INSTANCE( ) auf. Sollte die Factory
* Datenbankzugriffe machen, braucht sie ebenfalls einen Injektionspunkt.
* Der BCS-Versand selbst wird hier nicht getestet (Integrationstest ueber VF31).

CLASS ltc_send_mail_invoice DEFINITION DEFERRED.
CLASS zcl_bc_mail_nast_invo_mail DEFINITION LOCAL FRIENDS ltc_send_mail_invoice.


CLASS ltd_archive DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_bc_mail_nast_invo_archive.

    DATA received_documents  TYPE zbc_mail_nast_invo_arc_docs READ-ONLY.
    DATA received_sap_object TYPE saeanwdid READ-ONLY.
    DATA received_object_id  TYPE saeobjid READ-ONLY.
    DATA received_ar_object  TYPE saeobjart READ-ONLY.
    DATA call_count          TYPE i READ-ONLY.
ENDCLASS.


CLASS ltd_archive IMPLEMENTATION.
  METHOD zif_bc_mail_nast_invo_archive~archive.
    call_count          = call_count + 1.
    received_documents  = documents.
    received_sap_object = sap_object.
    received_object_id  = object_id.
    received_ar_object  = ar_object.
  ENDMETHOD.
ENDCLASS.


CLASS ltc_send_mail_invoice DEFINITION FINAL FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    DATA cut            TYPE REF TO zcl_bc_mail_nast_invo_mail.
    DATA archive_double TYPE REF TO ltd_archive.
    DATA pdf_content    TYPE xstring.

    METHODS setup.
    METHODS teardown.

    METHODS total_size_sums_all_documents FOR TESTING.
    METHODS file_name_gets_pdf_extension  FOR TESTING.
    METHODS file_name_keeps_extension     FOR TESTING.
    METHODS placeholder_has_invoice_nr    FOR TESTING.
    METHODS placeholder_has_invoice_date  FOR TESTING.
    METHODS archives_invoice_and_attachmts FOR TESTING.
    METHODS archive_uses_object_key       FOR TESTING.
    METHODS no_archiving_when_inactive    FOR TESTING.
    METHODS valid_pdf_is_accepted         FOR TESTING RAISING cx_static_check.
    METHODS non_pdf_type_is_rejected      FOR TESTING.
    METHODS invalid_pdf_data_is_rejected  FOR TESTING.
    METHODS empty_list_is_rejected        FOR TESTING.
    METHODS too_large_mail_is_rejected    FOR TESTING.
    METHODS archive_only_checks_pdf       FOR TESTING.
ENDCLASS.


CLASS ltc_send_mail_invoice IMPLEMENTATION.

  METHOD setup.
    pdf_content    = '255044462D312E37'. " "%PDF-1.7", 8 Byte
    archive_double = NEW #( ).
    cut = NEW #(
        mail_settings    = VALUE #( recipient_address = 'test@example.com'
                                    max_size_in_bytes = 100 )
        archive_settings = VALUE #( active              = abap_true
                                    sap_object          = 'VBRK'
                                    object_id           = '0090000001'
                                    doc_type            = 'ZINVOICE' )
        archiver         = archive_double ).
    cut->invoice_number = '0090000001'.
    cut->invoice_date   = '20251123'.
    cut->documents = VALUE #( ( document = pdf_content document_type = 'application/pdf' document_title = 'Rechnung' )
                              ( document = pdf_content document_type = 'application/pdf' document_title = 'Lieferschein' ) ).
  ENDMETHOD.


  METHOD teardown.
    CLEAR: cut, archive_double, pdf_content.
  ENDMETHOD.


  METHOD total_size_sums_all_documents.
    DATA(size) = zcl_bc_mail_nast_invo_mail=>calculate_total_size(
                   VALUE #( ( document = pdf_content ) ( document = pdf_content ) ( document = pdf_content ) ) ).
    cl_abap_unit_assert=>assert_equals( act = size exp = 24 ).
  ENDMETHOD.


  METHOD file_name_gets_pdf_extension.
    cl_abap_unit_assert=>assert_equals(
        act = zcl_bc_mail_nast_invo_mail=>get_file_name( VALUE #( document_title = 'Lieferschein' ) )
        exp = `Lieferschein.pdf` ).
  ENDMETHOD.


  METHOD file_name_keeps_extension.
    cl_abap_unit_assert=>assert_equals(
        act = zcl_bc_mail_nast_invo_mail=>get_file_name( VALUE #( document_title = 'Lieferschein.PDF' ) )
        exp = `Lieferschein.PDF` ).
  ENDMETHOD.


  METHOD placeholder_has_invoice_nr.
    DATA(placeholders) = VALUE zcl_sm_sta_send_mail=>ttyp_placeholder( ).

    cut->set_placeholders( CHANGING ci_placeholder = placeholders ).

    DATA(placeholder) = VALUE #( placeholders[ placeholder = zcl_bc_mail_nast_invo_mail=>placeholder_invoice_number ] OPTIONAL ).
    cl_abap_unit_assert=>assert_equals( act = placeholder-value exp = `90000001` ).
  ENDMETHOD.


  METHOD placeholder_has_invoice_date.
    DATA(placeholders) = VALUE zcl_sm_sta_send_mail=>ttyp_placeholder( ).

    cut->set_placeholders( CHANGING ci_placeholder = placeholders ).

    DATA(placeholder) = VALUE #( placeholders[ placeholder = zcl_bc_mail_nast_invo_mail=>placeholder_invoice_date ] OPTIONAL ).
    cl_abap_unit_assert=>assert_equals( act = placeholder-value exp = `23.11.2025` ).
  ENDMETHOD.


  METHOD archives_invoice_and_attachmts.
    cut->archive_documents( ).

    cl_abap_unit_assert=>assert_equals( act = archive_double->call_count exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( archive_double->received_documents ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = archive_double->received_ar_object exp = 'ZINVOICE' ).
    cl_abap_unit_assert=>assert_equals( act = archive_double->received_documents[ 1 ]-content exp = pdf_content ).
    cl_abap_unit_assert=>assert_equals( act = archive_double->received_documents[ 2 ]-content exp = pdf_content ).
  ENDMETHOD.


  METHOD archive_uses_object_key.
    cut->archive_documents( ).

    cl_abap_unit_assert=>assert_equals( act = archive_double->received_sap_object exp = 'VBRK' ).
    cl_abap_unit_assert=>assert_equals( act = archive_double->received_object_id exp = '0090000001' ).
  ENDMETHOD.


  METHOD no_archiving_when_inactive.
    cut->archive_settings-active = abap_false.

    cut->archive_documents( ).

    cl_abap_unit_assert=>assert_equals( act = archive_double->call_count exp = 0 ).
  ENDMETHOD.


  METHOD valid_pdf_is_accepted.
    cut->check_documents( ).

    cl_abap_unit_assert=>assert_equals( act = lines( cut->documents ) exp = 2 ).
  ENDMETHOD.


  METHOD non_pdf_type_is_rejected.
    cut->documents = VALUE #( ( document = pdf_content document_type = 'image/png' ) ).
    TRY.
        cut->check_documents( ).
        cl_abap_unit_assert=>fail( 'Ausnahme erwartet' ).
      CATCH zcx_sm_sta_send_mail ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.


  METHOD invalid_pdf_data_is_rejected.
    cut->documents = VALUE #( ( document = CONV xstring( '0011223344556677' ) document_type = 'application/pdf' ) ).
    TRY.
        cut->check_documents( ).
        cl_abap_unit_assert=>fail( 'Ausnahme erwartet' ).
      CATCH zcx_sm_sta_send_mail ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.


  METHOD empty_list_is_rejected.
    CLEAR cut->documents.
    TRY.
        cut->check_documents( ).
        cl_abap_unit_assert=>fail( 'Ausnahme erwartet' ).
      CATCH zcx_sm_sta_send_mail ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.


  METHOD too_large_mail_is_rejected.
    cut->total_size = 101.
    TRY.
        cut->check_size( ).
        cl_abap_unit_assert=>fail( 'Ausnahme erwartet' ).
      CATCH zcx_sm_sta_send_mail ##NO_HANDLER.
    ENDTRY.
  ENDMETHOD.


  METHOD archive_only_checks_pdf.
    TRY.
        cut->archive_invoice( invoice_number = '0090000001'
                              documents      = VALUE #( ( document = pdf_content document_type = 'text/plain' ) ) ).
        cl_abap_unit_assert=>fail( 'Ausnahme erwartet' ).
      CATCH zcx_sm_sta_send_mail ##NO_HANDLER.
    ENDTRY.
    cl_abap_unit_assert=>assert_equals( act = archive_double->call_count exp = 0 ).
  ENDMETHOD.

ENDCLASS.
