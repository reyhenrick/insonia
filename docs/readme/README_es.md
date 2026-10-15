[English](../../README.md) · [Português (Brasil)](README_pt-BR.md) · **Español** · [Français](README_fr.md) · [Deutsch](README_de.md) · [Italiano](README_it.md)

<p align="center">
  <img src="../assets/icon.png" width="96" height="96" alt="Icono de Insonia">
</p>

# Insonia

**Mantén tus agentes de programación trabajando con la tapa cerrada.**

Insonia mantiene tu Mac activo mientras se ejecutan agentes locales, compilaciones y pruebas. Puedes cerrar la tapa y alejarte sin que el ordenador entre en reposo. Si usas acceso remoto para seguir a tus agentes desde el móvil, tu Mac puede permanecer disponible en casa mientras estás fuera.

**[Descargar para Mac](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.dmg)**

macOS 26 o posterior · Apple silicon e Intel · Gratis y de código abierto

<p align="center">
  <img src="../assets/panel.png" width="380" alt="Panel de Insonia en la barra de menús con Mantener activo activado">
</p>

<a id="install-and-start"></a>

## Instalar

1. Abre el DMG y arrastra **Insonia** a **Aplicaciones**.
2. Abre Insonia y haz clic en el rayo de la barra de menús.
3. Activa **Mantener activo**, autoriza la solicitud de administrador de macOS si aparece y espera a que se active.

La app no cuenta con la notarización de Apple. Si macOS bloquea el primer inicio, sigue las [instrucciones de Apple](https://support.apple.com/es-es/102445) para abrirla desde **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**.

## Usar con agentes de programación

Inicia tu agente como de costumbre y activa **Mantener activo** antes de cerrar la tapa. Desactívalo cuando termines para restaurar el reposo normal.

Para los agentes que interactúan con ventanas del navegador o de otras apps, activa también **Permitir que los agentes usen la pantalla** con la tapa abierta y el Mac desbloqueado. Insonia reduce el brillo de la pantalla integrada al cerrar la tapa y lo restaura al volver a abrirla. Bloquear el Mac puede pausar este acceso visual.

Para acceder cuando estés fuera, mantén el Mac conectado a internet y usa los controles remotos de tu agente o la herramienta de acceso remoto que ya utilices. Insonia se encarga del reposo del Mac; el acceso remoto se configura por separado.

Mantén el Mac sobre una superficie ventilada mientras trabaja. Insonia se pausa cuando la batería llega al 15% o menos, si no está enchufado, o cuando macOS detecta una condición térmica grave.

## Actualizaciones

Insonia busca actualizaciones automáticamente. Usa **Buscar actualizaciones…** en el panel para instalar una versión. La instalación espera hasta que Mantener activo esté desactivado y la sesión haya terminado.

## Contribuir

El proyecto se distribuye bajo la [licencia MIT](../../LICENSE). Consulta [CONTRIBUTING.md](../../CONTRIBUTING.md) para obtener instrucciones de compilación y contribución, o [abre una issue](https://github.com/reyhenrick/insonia/issues/new/choose) para informar de un problema.

[Desinstalar](../../CONTRIBUTING.md#remove-a-local-installation) · [Seguridad](../../SECURITY.md) · [Versiones](https://github.com/reyhenrick/insonia/releases)
