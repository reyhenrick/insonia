[English](../../README.md) · [Português (Brasil)](README_pt-BR.md) · [Español](README_es.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · **Italiano**

<p align="center">
  <img src="../assets/icon.png" width="96" height="96" alt="Icona dell’app Insonia">
</p>

# Insonia

**I tuoi agenti di programmazione continuano a lavorare con il coperchio chiuso.**

Insonia mantiene il Mac attivo mentre vengono eseguiti agenti locali, build e test. Puoi chiudere il coperchio e allontanarti senza che il computer vada in stop. Se segui i tuoi agenti dal telefono tramite accesso remoto, il Mac può restare disponibile a casa mentre sei fuori.

**[Scarica per Mac](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.dmg)**

macOS 26 o successivo · Apple silicon e Intel · Gratuito e open source

<p align="center">
  <img src="../assets/panel.png" width="380" alt="Pannello di Insonia nella barra dei menu con Mantieni attivo abilitato">
</p>

<a id="install-and-start"></a>

## Installazione

1. Apri il DMG e trascina **Insonia** in **Applicazioni**.
2. Apri Insonia e fai clic sul fulmine nella barra dei menu.
3. Attiva **Mantieni attivo**, autorizza la richiesta di amministratore di macOS se compare e attendi l’attivazione.

L’app non è stata autenticata da Apple. Se macOS blocca il primo avvio, segui le [istruzioni di Apple](https://support.apple.com/it-it/102445) per aprirla da **Impostazioni di Sistema → Privacy e sicurezza → Apri comunque**.

## Usare con gli agenti di programmazione

Avvia il tuo agente come al solito e attiva **Mantieni attivo** prima di chiudere il coperchio. Disattiva l’opzione quando hai finito per ripristinare la normale modalità di stop.

Per gli agenti che interagiscono con le finestre del browser o di altre app, attiva anche **Consenti agli agenti di usare lo schermo** con il coperchio aperto e il Mac sbloccato. Insonia riduce la luminosità dello schermo integrato quando chiudi il coperchio e la ripristina quando lo riapri. Bloccare il Mac può mettere in pausa questo accesso visivo.

Per accedere mentre sei fuori, lascia il Mac connesso a Internet e usa i controlli remoti del tuo agente o lo strumento di accesso remoto che utilizzi già. Insonia gestisce la modalità di stop del Mac; l’accesso remoto si configura separatamente.

Tieni il Mac su una superficie ben ventilata mentre lavora. Insonia si mette in pausa quando la batteria raggiunge il 15% o meno, se il Mac è scollegato dall’alimentazione, oppure quando macOS segnala una condizione termica grave.

## Aggiornamenti

Insonia cerca automaticamente gli aggiornamenti. Usa **Cerca aggiornamenti…** nel pannello per installare una versione. L’installazione attende che Mantieni attivo sia disattivato e che la sessione sia terminata.

## Contribuire

Il progetto è distribuito con [licenza MIT](../../LICENSE). Consulta [CONTRIBUTING.md](../../CONTRIBUTING.md) per le istruzioni di compilazione e per contribuire, oppure [apri una issue](https://github.com/reyhenrick/insonia/issues/new/choose) per segnalare un problema.

[Disinstallare](../../CONTRIBUTING.md#remove-a-local-installation) · [Sicurezza](../../SECURITY.md) · [Versioni](https://github.com/reyhenrick/insonia/releases)
