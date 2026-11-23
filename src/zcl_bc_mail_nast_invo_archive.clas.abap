CLASS zcl_bc_mail_nast_invo_archive DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bc_mail_nast_invo_archive.

ENDCLASS.


CLASS zcl_bc_mail_nast_invo_archive IMPLEMENTATION.

  METHOD zif_bc_mail_nast_invo_archive~archive.
    " Die Ausfuehrung erfolgt erst nach dem COMMIT der rufenden LUW:
    " - Versandzeitpunkt 1/3: nach dem COMMIT von RSNAST00 bzw. VF31
    " - Versandzeitpunkt 4:   nach Ende der Verbuchung der Faktura
    " Fehler der Ablage fuehren so nie zu einem Verbuchungsabbruch.
    CALL FUNCTION 'Z_BC_MAIL_NAST_INVO_ARCHIVE'
      IN BACKGROUND TASK AS SEPARATE UNIT
      EXPORTING sap_object = sap_object
                object_id  = object_id
                ar_object  = ar_object
                documents  = documents.
  ENDMETHOD.

ENDCLASS.
