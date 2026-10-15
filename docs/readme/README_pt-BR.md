[English](../../README.md) · **Português (Brasil)** · [Español](README_es.md) · [Français](README_fr.md) · [Deutsch](README_de.md) · [Italiano](README_it.md)

<p align="center">
  <img src="../assets/icon.png" width="96" height="96" alt="Ícone do Insonia">
</p>

# Insonia

**Mantenha seus agentes de programação trabalhando com a tampa fechada.**

O Insonia mantém o Mac acordado enquanto agentes locais, builds e testes são executados. Você pode fechar a tampa e se afastar sem que o computador entre em repouso. Se você acompanha seus agentes pelo celular com acesso remoto, o Mac pode continuar disponível em casa enquanto você está fora.

**[Baixar para Mac](https://github.com/reyhenrick/insonia/releases/latest/download/Insonia-macOS.dmg)**

macOS 26 ou posterior · Apple silicon e Intel · Gratuito e de código aberto

<p align="center">
  <img src="../assets/panel.png" width="380" alt="Painel do Insonia na barra de menus com Manter acordado ativado">
</p>

<a id="install-and-start"></a>

## Instalar

1. Abra o DMG e arraste o **Insonia** para **Aplicativos**.
2. Abra o Insonia e clique no raio na barra de menus.
3. Ative **Manter acordado**, autorize no diálogo de administrador do macOS se solicitado e aguarde a ativação.

O app não foi autenticado pela Apple. Se o macOS bloquear a primeira abertura, siga as [instruções da Apple](https://support.apple.com/pt-br/102445) para abri-lo em **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**.

## Usar com agentes de programação

Inicie seu agente como de costume e ative **Manter acordado** antes de fechar a tampa. Desative quando terminar para restaurar o repouso normal.

Para agentes que interagem com janelas de navegadores ou aplicativos, ative também **Permitir uso da tela por agentes** com a tampa aberta e o Mac desbloqueado. O Insonia reduz o brilho da tela interna ao fechar a tampa e o restaura ao reabri-la. Bloquear o Mac pode pausar esse acesso visual.

Para acessar de fora de casa, mantenha o Mac conectado à internet e use os controles remotos do seu agente ou a ferramenta de acesso remoto que você já utiliza. O Insonia cuida do repouso do Mac; o acesso remoto é configurado separadamente.

Mantenha o Mac em uma superfície ventilada enquanto ele trabalha. O Insonia pausa quando a bateria chega a 15% ou menos, se estiver fora da tomada, ou quando o macOS detecta uma condição térmica grave.

## Atualizações

O Insonia busca atualizações automaticamente. Use **Buscar atualizações…** no painel para instalar uma versão. A instalação aguarda até que Manter acordado esteja desativado e a sessão tenha terminado.

## Contribuir

O projeto é distribuído sob a [licença MIT](../../LICENSE). Veja [CONTRIBUTING.md](../../CONTRIBUTING.md) para instruções de build e contribuições, ou [abra uma issue](https://github.com/reyhenrick/insonia/issues/new/choose) para relatar um problema.

[Desinstalar](../../CONTRIBUTING.md#remove-a-local-installation) · [Segurança](../../SECURITY.md) · [Versões](https://github.com/reyhenrick/insonia/releases)
