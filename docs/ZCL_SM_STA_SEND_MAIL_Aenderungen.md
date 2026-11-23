# Änderungen an der Basisklasse ZCL_SM_STA_SEND_MAIL

Die Basisklasse liegt nicht in diesem Paket und wird deshalb nicht über abapGit ausgeliefert. Die Änderungen bitte manuell im System vornehmen, **bevor** die Objekte dieses Repos aktiviert werden.

Die Defaults entsprechen exakt dem bisherigen Verhalten. Bestehende Unterklassen sind nicht betroffen.

## 1. PROTECTED SECTION: neue Methoden

```abap
    "! Hook nach Erzeugung des Dokuments, vor dem Versand
    METHODS before_send
      RAISING cx_bcs
              zcx_sm_sta_exception.

    "! Darf send_mail selbst COMMIT WORK ausfuehren?
    METHODS is_commit_allowed
      RETURNING VALUE(result) TYPE abap_bool.

    "! Fehlerbild beim Senden anzeigen?
    METHODS with_error_screen
      RETURNING VALUE(result) TYPE abap_bool.
```

## 2. Implementierung der neuen Methoden

```abap
  METHOD before_send ##NEEDED.
    " Leer: kann in Unterklassen redefiniert werden
  ENDMETHOD.


  METHOD is_commit_allowed.
    result = xsdbool( cl_system_transaction_state=>get_in_update_task( ) = 0 ).
  ENDMETHOD.


  METHOD with_error_screen.
    result = abap_true.
  ENDMETHOD.
```

## 3. SEND_MAIL vollständig ersetzen

Zusaetzlich wird die gefangene Ausnahme als PREVIOUS weitergereicht, damit die
Ursache im NAST-Protokoll bzw. beim Aufrufer sichtbar bleibt. Generierte
Ausnahmeklassen bieten PREVIOUS im Konstruktor standardmaessig an, bitte pruefen.

```abap
  METHOD send_mail.
    TRY.
        mi_tline = ii_tline.

        get_data( id_key = id_key ii_key = ii_key ii_pdf_data = ii_pdf_data ).

        mo_send_request = cl_bcs=>create_persistent( ).

        mo_send_request->set_sender( get_sender( ) ).
        IF id_email IS NOT INITIAL.
          set_recipient_address( id_email = id_email ).
        ENDIF.

        mo_send_request->add_recipient( i_recipient = get_recipient( )
                                        i_express   = abap_true ).
        mo_send_request->set_disclosure( me->set_disclosure_type( ) ).

        add_copy_to( ).

        generate_body( ).

        create_document( ).

        attach_documents( ii_pdf_data ).

        mo_send_request->set_document( mo_document ).
        IF strlen( md_subject ) > 50.
          mo_send_request->set_message_subject( md_subject ). " Hinweis 860075
        ENDIF.

        before_send( ).

        mo_send_request->send( i_with_error_screen = with_error_screen( ) ).

        IF is_commit_allowed( ).
          COMMIT WORK.
        ENDIF.

      CATCH cx_bcs INTO DATA(bcs_error).
        RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
          EXPORTING textid   = zcx_sm_sta_send_mail=>zcx_error
                    previous = bcs_error.

      CATCH zcx_sm_sta_exception INTO DATA(error).
        RAISE EXCEPTION TYPE zcx_sm_sta_send_mail
          EXPORTING textid   = zcx_sm_sta_send_mail=>zcx_error
                    previous = error.
    ENDTRY.
  ENDMETHOD.
```

## 4. Hinweis zur Verwendung

MI_BODY wird in GENERATE_BODY nie geleert. Pro E-Mail daher immer eine neue Instanz erzeugen, sonst verdoppelt sich der Body bei einem zweiten Aufruf.
