INTERFACE zif_bc_mail_nast_invo_archive
  PUBLIC.

  "! Registriert die ArchiveLink-Ablage der Dokumente.
  "! Zeile 1 (Rechnung) wird unveraendert abgelegt, die Anhaenge ab Zeile 2
  "! werden zu einem PDF zusammengefuehrt; beide mit
  "! Dokumentart AR_OBJECT abgelegt.
  "! Die Ausfuehrung erfolgt nach dem COMMIT der rufenden LUW.
  METHODS archive
    IMPORTING sap_object TYPE saeanwdid
              object_id  TYPE saeobjid
              ar_object  TYPE saeobjart
              documents  TYPE zbc_mail_nast_invo_arc_docs.

ENDINTERFACE.
