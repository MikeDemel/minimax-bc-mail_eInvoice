# Customizing Nachrichtenart ZEIM

## NACE (Applikation V3)

Nachrichtenart ZEIM am einfachsten als Kopie der bestehenden Rechnungsnachricht (z. B. RD00) anlegen.

| Bereich | Einstellung |
|---|---|
| Allgemeine Daten | Zugriffsfolge wie Rechnungsnachricht, Zugriff auf Konditionen aktiv |
| Vorschlagswerte | Versandzeitpunkt 1, Sendemedium 5 (Externe Sendung), Partnerrolle RE |
| Ablagesystem | Ablagemodus 3 (Drucken und Ablegen), Dokumentart `ZEDI_INVOI` wie beim bisherigen Druckprozess |
| Verarbeitungsroutinen | Medium 5, Programm `ZBC_MAIL_NAST_INVO_PROCESS`, FORM-Routine `ENTRY`. Das Formular wird hier nicht ausgewertet: Das PDF erzeugt `/IX2/EINV_GET_PDF` mit dem TNAPR-Eintrag der Druckausgabe (Nachrichtenart `ZIF_STA_SD_INV_NAST=>CO_MSG_TYPE_INVOICE_MAIL`, Medium `CO_TRANS_MEDIUM_PRINT_OUTPUT`), der dafür gepflegt sein muss |
| Partnerrollen | Medium 5 mit Partnerrolle RE |
| Nachrichtenschema | ZEIM ins Faktura-Schema aufnehmen, Bedingung wie RD00 (Standard: 62) |
| Konditionssätze (VV31) | Medium 5, Zeitpunkt 1, Kommunikation: Archivierungsmodus 3 |

Archivierungsmodus 2 (nur Ablegen) wird vom Programm unterstützt: Dann wird abgelegt, aber nicht versendet.

## ArchiveLink

- Rechnung und alle Anhänge werden im tRFC `Z_BC_MAIL_NAST_INVO_ARCHIVE` über ADS (`CL_RSPO_PDF_MERGE`) zu einem PDF zusammengeführt und als ein Dokument mit der Dokumentart aus NACE > Ablagesystem abgelegt (Fallback `ZEDI_INVOI`). Objekt-ID aus `TOA_DARA-OBJECT_ID`, sonst Standardaufbau `NAST-OBJKY` (30 Stellen, mit Leerzeichen) + `NAST-OPTARCNR`, z. B. `9111001807` + `0018190440`. Damit ist jede Ablage eindeutig einer Nachricht zugeordnet und wird aus der Nachricht heraus gefunden.
- OAC3: `VBRK` / `ZEDI_INVOI` (bzw. die eingetragene Dokumentart, Repository wie Druckprozess, z. B. `V4`) mit dem Content-Repository verknüpfen.
- Schlägt das Zusammenführen fehl (Meldung `ZBC_MAIL_NAST_INVO` 014), bleibt der tRFC in SM58 und kann dort wiederholt werden. Die E-Mail ist zu dem Zeitpunkt bereits versendet.

## Texte (SO10, Text-ID ST)

- `ZBC_MAIL_NAST_INVO_BODY_<VKORG>`: Body; der Texttitel wird zum Betreff. Beide dürfen die Platzhalter `&INVOICE_NUMBER&` (Fakturanummer ohne führende Nullen) und `&INVOICE_DATE&` (Fakturadatum `VBRK-FKDAT` im Format TT.MM.JJJJ) enthalten.
- `ZCA_<BUKRS>_SIGNATURE`: Signatur (Buchungskreis der Faktura).

## Empfänger

E-Mail-Adresse aus Tabelle `ZBC_IDOC_JOU_ACR` (Feld `EMAIL`) zum Nachrichtenpartner (`NAST-PARNR`). Fehlt sie, bricht die Verarbeitung mit Meldung `ZBC01` 015 ab.

## Absender

E-Mail-Adresse der Verkaufsorganisation (OVX5, Adresse). Ohne Adresse versendet die Basisklasse mit dem SAP-Benutzer, im Batch also mit dem RSNAST00-User.

## Jobs und Monitoring

- RSNAST00 periodisch mit Variante: Applikation V3, Nachrichtenart ZEIM, Medium 5.
- SAPconnect-Sendejob (SCOT).
- SOST für den Versand, SM58 für die Ablage-tRFCs (`Z_BC_MAIL_NAST_INVO_ARCHIVE`), NAST-Protokoll in VF03.

## Versandzeitpunkt 4

Das Programm lässt keine Exception aus `ENTRY` heraus und legt per tRFC nach Ende der Verbuchung ab. `ZCL_BC_MAIL_NAST_INVO_MAIL` redefiniert `IS_COMMIT_ALLOWED` und `WITH_ERROR_SCREEN` nicht mehr; ob in der Verbuchung ein `COMMIT WORK` oder ein Fehlerbild unterbleibt, hängt damit vom Default der Basisklasse ab (siehe [ZCL_SM_STA_SEND_MAIL_Aenderungen.md](ZCL_SM_STA_SEND_MAIL_Aenderungen.md)). Vor dem Einsatz von Zeitpunkt 4 prüfen. Auch `/IX2/EINV_GET_PDF` muss ohne Dialog laufen.
