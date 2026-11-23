INTERFACE zif_bc_mail_nast_invo_archive
  PUBLIC.

  "! Registriert die ArchiveLink-Ablage der Dokumente.
  "! Die Ausfuehrung erfolgt nach dem COMMIT der rufenden LUW.
  METHODS archive
    IMPORTING sap_object TYPE saeanwdid
              object_id  TYPE saeobjid
              documents  TYPE zbc_mail_nast_invo_arc_docs.

ENDINTERFACE.
