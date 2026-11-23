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
- Dokumente ermitteln: Zeile 1 = Rechnungs-PDF (Adobe-Formular aus NACE), ab Zeile 2 = weitere
  PDF-Anhänge. Nur PDFs (MIME-Typ und Signatur `%PDF-` werden geprüft).
- E-Mail per BCS über `ZCL_BC_MAIL_NAST_INVO_MAIL` (erbt von `ZCL_SM_STA_SEND_MAIL`). Empfänger
  = Standard-Mailadresse des Nachrichtenpartners (`NAST-PARVW`, z. B. RE), Absender = Adresse der
  Verkaufsorganisation, Body / Signatur aus SO10-Texten `ZBC_MAIL_NAST_INVO_BODY_<VKORG>` /
  `_SIGN_<VKORG>`.
- Nach erfolgreichem Versand ArchiveLink-Ablage per tRFC (`Z_BC_MAIL_NAST_INVO_ARCHIVE` →
  `ARCHIV_CREATE_TABLE`). Archivierungsmodus 2 = nur ablegen, kein Versand.
- Protokoll über `NAST_PROTOCOL_UPDATE` mit Nachrichtenklasse `ZBC_MAIL_NAST_INVO`.

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
| `ZBC_MAIL_NAST_INVO` / `Z_BC_MAIL_NAST_INVO_ARCHIVE` | Funktionsgruppe / RFC-Baustein | Ablage über `ARCHIV_CREATE_TABLE`, Fehler → SM58 |
| `ZBC_MAIL_NAST_INVO_ARC_DOC` / `_ARC_DOCS` | Struktur / Tabellentyp | Dokumente für die Ablage (`AR_OBJECT`, `CONTENT`) |
| `ZBC_MAIL_NAST_INVO` | Nachrichtenklasse | Meldungen für NAST-Protokoll und SM58 |

Customizing (nicht im Repo): Nachrichtenart `ZEIM`, Dokumentarten `SDOINVOICE` / `ZSDINVATT`
(OAC2 / OAC3), SO10-Texte, RSNAST00-Job. Details in `docs/NACE-Customizing.md`.

### Abhängigkeiten außerhalb des Repos

Nicht eingecheckt und hier nicht zu ändern: `ZCL_SM_STA_SEND_MAIL` (benötigt die Hooks
`before_send`, `is_commit_allowed`, `with_error_screen`, siehe
`docs/ZCL_SM_STA_SEND_MAIL_Aenderungen.md`), `ZCX_SM_STA_SEND_MAIL`, `ZCX_SM_STA_EXCEPTION`,
`ZCL_SM_STA_MSG_HANDLER_FACTORY`, Struktur `ZSTA_BO_DIR_DOCS` und alle SAP-Standardobjekte.
Bevor Signaturen dieser Objekte verwendet werden, im System prüfen statt raten.

## Laufzeitregeln (wichtig)

Der Code läuft auch in der Verbuchung (Versandzeitpunkt 4). Deshalb:

- Kein `COMMIT WORK`, kein Dialog, keine Popups (`is_commit_allowed` / `with_error_screen`
  liefern `abap_false`). PDF-Erzeugung nur mit `nodialog = abap_true`, `getpdf = abap_true`.
- Aus `FORM entry` darf keine Ausnahme herauslaufen: alles fangen, ins NAST-Protokoll schreiben,
  `return_code = 1`.
- Ablage nur per tRFC und erst nach erfolgreichem Versand (keine Dubletten bei Wiederholung).
- Pro E-Mail eine neue Instanz von `ZCL_BC_MAIL_NAST_INVO_MAIL` (`MI_BODY` der Basisklasse wird
  nicht geleert).

## Codestil

- Neuer Code folgt den globalen Leitplanken: 7.50-Syntax, sprechende Namen ohne Präfixe,
  Abhängigkeiten per Interface und Konstruktor injiziert.
- Der Bestand schreibt Schlüsselwörter groß; innerhalb einer Datei daran anschließen.
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

## Offene Punkte

In `ZBC_MAIL_NAST_INVO_PROCESS` sind `get_invoice_pdf` und `get_attachments` noch `TODO`.

## Sprache

Dokumentation und Commit-Nachrichten auf Deutsch; DDIC-Texte und Nachrichtentexte auf Deutsch
(Mastersprache `D`).
