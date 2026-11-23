# MINIMAX-BC-MAIL_EINVOICE

Mailversand aus NAST zu Rechnungen (Nachrichtenart ZEIM): Rechnungs-PDF und weitere PDF-Anhänge per E-Mail, Ablage per ArchiveLink.

## Ablauf

1. `FORM ENTRY` in `ZBC_MAIL_NAST_INVO_PROCESS` wird von der Nachrichtensteuerung gerufen.
2. Rechnungs-PDF über `/IX2/EINV_GET_PDF`. Der Baustein bekommt eine eigene NAST (Nachrichtenart `ZIF_STA_SD_INV_NAST=>CO_MSG_TYPE_INVOICE_MAIL`) und den TNAPR-Eintrag der Druckausgabe (Medium `CO_TRANS_MEDIUM_PRINT_OUTPUT`). Vorher wird `ZCL_IDOC_INVO_JOUBINI_MODE_FAC` auf „nur Anhang“ gesetzt.
3. Weitere PDF-Anhänge über `ZCL_IDOC_INVO_JOUBINI_ATTA_FAC=>GET_INSTANCE( )->GET_MAIL_ATTACHMENTS( )`.
4. Empfänger aus `ZBC_IDOC_JOU_ACR-EMAIL` zum Nachrichtenpartner (`NAST-PARNR`), Absender aus der Adresse der Verkaufsorganisation.
5. Versand per BCS über `ZCL_BC_MAIL_NAST_INVO_MAIL`, danach Ablage per tRFC: die Rechnung wird unverändert abgelegt, die Anhänge werden zu einem PDF zusammengeführt (`CL_RSPO_PDF_MERGE`, ADS) und als zweites Dokument abgelegt. In der Anlagenliste erscheinen sie als „Rechnung <Nr>“ und „Anlagen zu Rechnung <Nr>“ (Beschreibung und Dateiname per `ARCHIV_CREATE_TABLE`, Tabelle `TOAAT`).
6. Meldungen über `ZCL_SM_STA_MSG_HANDLER_FACTORY` ins NAST-Protokoll.

## Objekte

| Objekt | Typ | Zweck |
|---|---|---|
| `ZBC_MAIL_NAST_INVO_PROCESS` | Programm | Verarbeitungsprogramm für NACE (FORM `ENTRY`) |
| `ZCL_BC_MAIL_NAST_INVO_MAIL` | Klasse | E-Mail-Versand, erbt von `ZCL_SM_STA_SEND_MAIL` |
| `ZIF_BC_MAIL_NAST_INVO_ARCHIVE` | Interface | Ablage (für Unit-Tests mockbar) |
| `ZCL_BC_MAIL_NAST_INVO_ARCHIVE` | Klasse | Ablage per tRFC |
| `ZBC_MAIL_NAST_INVO` / `Z_BC_MAIL_NAST_INVO_ARCHIVE` | Funktionsgruppe / RFC-Baustein | PDFs zusammenführen, Ablage über `ARCHIV_CREATE_TABLE` |
| `ZBC_MAIL_NAST_INVO_ARC_DOC` / `ZBC_MAIL_NAST_INVO_ARC_DOCS` | Struktur / Tabellentyp | PDF-Inhalte für die Ablage (`CONTENT`) |
| `ZBC_MAIL_NAST_INVO` | Nachrichtenklasse | Meldungen für NAST-Protokoll und SM58 |

## Voraussetzungen

- Änderungen an der Basisklasse `ZCL_SM_STA_SEND_MAIL`: siehe [docs/ZCL_SM_STA_SEND_MAIL_Aenderungen.md](docs/ZCL_SM_STA_SEND_MAIL_Aenderungen.md)
- `ZCX_SM_STA_SEND_MAIL` erbt von `ZCX_SM_STA_EXCEPTION`.
- Struktur `ZSTA_BO_DIR_DOCS` mit `DOCUMENT_NR`, `DOCUMENT_TITLE`, `DOCUMENT_SIZE`, `DOCUMENT_TYPE`.
- E-Invoice-Komponenten: `/IX2/EINV_GET_PDF`, `/IX2/CX_EINVOICE_EXCEPTION`, `ZCL_IDOC_INVO_JOUBINI_MODE_FAC`, `ZCL_IDOC_INVO_JOUBINI_ATTA_FAC`, `ZIF_STA_SD_INV_NAST`, `ZIF_STA_SD_INV_FORM`.
- Tabelle `ZBC_IDOC_JOU_ACR` mit E-Mail-Adresse je Kunde.
- Nachrichtenklasse `ZBC01` (Meldungen 009 „kein PDF“, 015 „keine Empfängeradresse“).
- Typ des Parameters `FLENGTH` von `ARCHIV_CREATE_TABLE` in SE37 prüfen (`LIKE SAPB-LENGTH`).

## Konvention

Die Dokumenttabelle enthält in Zeile 1 die Rechnung, ab Zeile 2 die Anhänge. Es werden nur PDFs akzeptiert (MIME-Typ und PDF-Signatur werden geprüft).

## Customizing

Siehe [docs/NACE-Customizing.md](docs/NACE-Customizing.md).
