# MINIMAX-BC-MAIL_EINVOICE

Mailversand aus NAST zu Rechnungen (Nachrichtenart ZEIM): Rechnungs-PDF und weitere PDF-Anhänge per E-Mail, Ablage per ArchiveLink.

## Objekte

| Objekt | Typ | Zweck |
|---|---|---|
| `ZBC_MAIL_NAST_INVO_PROCESS` | Programm | Verarbeitungsprogramm für NACE (FORM `ENTRY`) |
| `ZCL_BC_MAIL_NAST_INVO_MAIL` | Klasse | E-Mail-Versand, erbt von `ZCL_SM_STA_SEND_MAIL` |
| `ZIF_BC_MAIL_NAST_INVO_ARCHIVE` | Interface | Ablage (für Unit-Tests mockbar) |
| `ZCL_BC_MAIL_NAST_INVO_ARCHIVE` | Klasse | Ablage per tRFC |
| `ZBC_MAIL_NAST_INVO` / `Z_BC_MAIL_NAST_INVO_ARCHIVE` | Funktionsgruppe / RFC-Baustein | Ablage über `ARCHIV_CREATE_TABLE` |
| `ZBC_MAIL_NAST_INVO_ARC_DOC` / `ZBC_MAIL_NAST_INVO_ARC_DOCS` | Struktur / Tabellentyp | Dokumente für die Ablage |
| `ZBC_MAIL_NAST_INVO` | Nachrichtenklasse | Meldungen für NAST-Protokoll und SM58 |

## Voraussetzungen

- Änderungen an der Basisklasse `ZCL_SM_STA_SEND_MAIL`: siehe [docs/ZCL_SM_STA_SEND_MAIL_Aenderungen.md](docs/ZCL_SM_STA_SEND_MAIL_Aenderungen.md)
- `ZCX_SM_STA_SEND_MAIL` erbt von `ZCX_SM_STA_EXCEPTION`.
- Struktur `ZSTA_BO_DIR_DOCS` mit `DOCUMENT_NR`, `DOCUMENT_TITLE`, `DOCUMENT_SIZE`, `DOCUMENT_TYPE`.
- Typ des Parameters `FLENGTH` von `ARCHIV_CREATE_TABLE` in SE37 prüfen (`LIKE SAPB-LENGTH`).

## Offene Punkte

In `ZBC_MAIL_NAST_INVO_PROCESS` sind `GET_INVOICE_PDF` und `GET_ATTACHMENTS` mit `TODO` markiert und müssen mit der bestehenden PDF- bzw. Anhangsermittlung gefüllt werden.

## Konvention

Die Dokumenttabelle enthält in Zeile 1 die Rechnung, ab Zeile 2 die Anhänge. Es werden nur PDFs akzeptiert (MIME-Typ und PDF-Signatur werden geprüft).

## Customizing

Siehe [docs/NACE-Customizing.md](docs/NACE-Customizing.md).
