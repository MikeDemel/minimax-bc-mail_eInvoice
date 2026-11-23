# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Die allgemeinen ABAP-Leitplanken (7.50-Syntax, keine Präfixe, SALV, ABAP Unit mit
`cl_abap_unit_assert`, keine Test-Seams) stehen in der globalen `CLAUDE.md` des Benutzers
(`~/.claude/CLAUDE.md`). Diese Datei enthält das Repo-Spezifische.

## Was dieses Repo ist

Mailversand aus der Nachrichtensteuerung (NAST) zu Rechnungen: Nachrichtenart **`ZEIM`**
(Applikation V3, Sendemedium 5 „Externe Sendung"). Fachlicher Ablauf:

- `FORM entry` in `ZBC_MAIL_NAST_INVO_PROCESS` wird aus der Nachrichtensteuerung gerufen
  (RSNAST00 / VF31 bei Versandzeitpunkt 1/3, Verbuchung der Faktura bei Zeitpunkt 4).
- Dokumente ermitteln: Zeile 1 = Rechnungs-PDF über `/IX2/EINV_GET_PDF` (eigene NAST mit
  `ZIF_STA_SD_INV_NAST=>co_msg_type_invoice_mail`, TNAPR der Druckausgabe; vorher
  `ZCL_IDOC_INVO_JOUBINI_MODE_FAC` auf „nur Anhang“), ab Zeile 2 = Anhänge aus
  `ZCL_IDOC_INVO_JOUBINI_ATTA_FAC=>get_instance( )->get_mail_attachments( )`. Nur PDFs (MIME-Typ
  und Signatur `%PDF-` werden geprüft). Leeres PDF → Ausnahme mit Meldung `ZBC01` 009.
- E-Mail per BCS über `ZCL_BC_MAIL_NAST_INVO_MAIL` (erbt von `ZCL_SM_STA_SEND_MAIL`). Empfänger
  aus `ZBC_IDOC_JOU_ACR-EMAIL` zu `NAST-PARNR` (fehlt → `ZBC01` 015), Absender = Adresse der
  Verkaufsorganisation, Body / Signatur aus SO10-Texten `ZBC_MAIL_NAST_INVO_BODY_<VKORG>` /
  `ZCA_<BUKRS>_SIGNATURE`.
- Nach erfolgreichem Versand ArchiveLink-Ablage per tRFC (`Z_BC_MAIL_NAST_INVO_ARCHIVE`):
  Rechnung (Zeile 1) wird unverändert abgelegt, die Anhänge werden über `CL_RSPO_PDF_MERGE` (ADS) zu einem PDF zusammengeführt und als zweites Dokument
  abgelegt (das Rechnungs-PDF aus `/IX2/EINV_GET_PDF` lehnt ADS mit RC 107 ab). Beide mit einer Dokumentart (NACE > Ablagesystem, Fallback `ZEDI_INVOI` wie im bisherigen Druckprozess) per `ARCHIV_CREATE_TABLE`
  abgelegt. Archivierungsmodus 2 = nur ablegen, kein Versand.
- Protokoll: Meldungen sammeln über `ZCL_SM_STA_MSG_HANDLER_FACTORY=>get_instance( )` (liefert
  immer eine neue Instanz), dann per `NAST_PROTOCOL_UPDATE` ins NAST-Protokoll. Eigene Meldungen
  in Nachrichtenklasse `ZBC_MAIL_NAST_INVO`, Fehler der Ermittlung in `ZBC01`.

Zielsystem ist SAP ECC 6.0 auf NetWeaver 7.50 (SD), kein S/4HANA.

Es gibt keine lokale Toolchain. ABAP wird im SAP-System (ADT oder SE80) syntaxgeprüft, aktiviert
und getestet. Hier gelten nur `git`-Kommandos; keine Build-, Lint- oder Testkommandos erfinden.
Commits und Pushes nur auf ausdrückliche Anweisung; Commit-Nachrichten auf Deutsch, im Imperativ.

abapGit-Repository (`.abapgit.xml`: `STARTING_FOLDER=/src/`, `FOLDER_LOGIC=PREFIX`, Mastersprache
`D`). Alle Objekte liegen flach in `src/` als `<name>.<typ>.abap` + `<name>.<typ>.xml`; Tests in
`.clas.testclasses.abap`, Funktionsgruppen als `<fugr>.fugr.*`. Dateien UTF-8, XML mit BOM.
Fachliche Doku in `docs/` (Customizing, nötige Änderungen an der Basisklasse).

## Objekte

| Objekt | Typ | Zweck |
| --- | --- | --- |
| `ZBC_MAIL_NAST_INVO_PROCESS` | Programm | Verarbeitungsprogramm für NACE (`FORM entry`), lokale Klassen `lcl_invoice_mail`, `lcl_nast_protocol` |
| `ZCL_BC_MAIL_NAST_INVO_MAIL` | Klasse | E-Mail-Versand und Ablage-Anstoß, erbt von `ZCL_SM_STA_SEND_MAIL` |
| `ZIF_BC_MAIL_NAST_INVO_ARCHIVE` | Interface | Ablage, per Konstruktor injizierbar (Test-Double in den Unit-Tests) |
| `ZCL_BC_MAIL_NAST_INVO_ARCHIVE` | Klasse | Ablage per tRFC (`IN BACKGROUND TASK AS SEPARATE UNIT`) |
| `ZBC_MAIL_NAST_INVO` / `Z_BC_MAIL_NAST_INVO_ARCHIVE` | Funktionsgruppe / RFC-Baustein | PDFs zusammenführen und über `ARCHIV_CREATE_TABLE` ablegen, Fehler → SM58 |
| `ZBC_MAIL_NAST_INVO_ARC_DOC` / `_ARC_DOCS` | Struktur / Tabellentyp | PDF-Inhalte für die Ablage (`CONTENT`) |
| `ZBC_MAIL_NAST_INVO` | Nachrichtenklasse | Meldungen für NAST-Protokoll und SM58 |

Customizing (nicht im Repo): Nachrichtenart `ZEIM`, Dokumentart `ZEDI_INVOI` (wie Druckprozess) bzw.
eigene PDF-Dokumentart (OAC2 / OAC3), ADS für das Zusammenführen, SO10-Texte, RSNAST00-Job. Details in `docs/NACE-Customizing.md`.

### Abhängigkeiten außerhalb des Repos

Nicht eingecheckt und hier nicht zu ändern: `ZCL_SM_STA_SEND_MAIL` (benötigt die Hooks
`before_send`, `is_commit_allowed`, `with_error_screen`, siehe
`docs/ZCL_SM_STA_SEND_MAIL_Aenderungen.md`), `ZCX_SM_STA_SEND_MAIL`, `ZCX_SM_STA_EXCEPTION`,
`ZCL_SM_STA_MSG_HANDLER_FACTORY` / `ZIF_SM_STA_MSG_HANDLER`, Struktur `ZSTA_BO_DIR_DOCS`, die
E-Invoice-Komponenten (`/IX2/EINV_GET_PDF`, `/IX2/CX_EINVOICE_EXCEPTION`,
`ZCL_IDOC_INVO_JOUBINI_*`, `ZIF_STA_SD_INV_NAST`, `ZIF_STA_SD_INV_FORM`), Tabelle
`ZBC_IDOC_JOU_ACR`, Nachrichtenklasse `ZBC01` und alle SAP-Standardobjekte.
Bevor Signaturen dieser Objekte verwendet werden, im System prüfen statt raten.

## Laufzeitregeln (wichtig)

Der Code läuft auch in der Verbuchung (Versandzeitpunkt 4). Deshalb:

- Kein `COMMIT WORK`, kein Dialog, keine Popups. `ZCL_BC_MAIL_NAST_INVO_MAIL` redefiniert
  `is_commit_allowed` / `with_error_screen` nicht mehr; es gilt der Default der Basisklasse
  (vor Einsatz von Zeitpunkt 4 prüfen).
- Aus `FORM entry` darf keine Ausnahme herauslaufen: alles fangen, ins NAST-Protokoll schreiben,
  `return_code = 1`.
- Ablage nur per tRFC und erst nach erfolgreichem Versand (keine Dubletten bei Wiederholung).
- Pro E-Mail eine neue Instanz von `ZCL_BC_MAIL_NAST_INVO_MAIL` (`MI_BODY` der Basisklasse wird
  nicht geleert).

## Codestil

- Neuer Code folgt den globalen Leitplanken: 7.50-Syntax, sprechende Namen ohne Präfixe,
  Abhängigkeiten per Interface und Konstruktor injiziert.
- Schlüsselwörter klein (Pretty Printer im System).
- Redefinierte Methoden der Basisklasse behalten deren Parameternamen (`ro_sender`,
  `rd_email_string`, `ci_placeholder` …).
- Nachrichten über Nachrichtenklasse `ZBC_MAIL_NAST_INVO`, nicht als freier Text.
- DDIC-Kurztexte und Nachrichtentexte auf Deutsch; Code-Bezeichner englisch. Kommentare im
  Bestand sind deutsch (ohne Umlaute), daran anschließen.

## Tests

`ZCL_BC_MAIL_NAST_INVO_MAIL` hat lokale Tests (`risk level harmless`, `duration short`,
`cl_abap_unit_assert`) mit Test-Double `ltd_archive` für `ZIF_BC_MAIL_NAST_INVO_ARCHIVE`.
Der BCS-Versand selbst wird nicht unit-getestet (Integrationstest über VF31). Neue Tests folgen
demselben Muster.

## Sprache

Dokumentation und Commit-Nachrichten auf Deutsch; DDIC-Texte und Nachrichtentexte auf Deutsch
(Mastersprache `D`).
