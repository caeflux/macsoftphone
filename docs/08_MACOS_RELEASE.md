# 08 — Build, Assinatura e Release macOS

## Objetivo

Preparar o app para distribuição controlada em macOS, primeiro para testes internos e depois para clientes/revendas.

## Ambientes

### Development

- Logs mais detalhados.
- Endpoints de teste.
- Feature flags experimentais.
- Build local.

### Staging/Homologação

- Endpoints de homologação.
- Logs sanitizados.
- Builds para equipe e clientes piloto.

### Production

- Endpoints finais.
- Logs mínimos e seguros.
- Assinatura/notarização quando aplicável.
- Versão white label final.

## Versionamento

Usar versionamento semântico:

```text
MAJOR.MINOR.PATCH
```

Exemplo:

- `0.1.0` — MVP interno.
- `0.2.0` — chamadas recebidas e histórico.
- `0.3.0` — white label inicial.
- `1.0.0` — primeira versão comercial.
- `2.0.0` — white label runtime (editor de tema, glassmorphism, modo compacto).

## Empacotamento local (build de teste interno)

O instalador de teste é gerado por script versionado no repositório:

```bash
./packaging/package-app.sh
```

Saída em `dist/` (ignorado pelo git): `Flux Softphone.app` e
`FluxSoftphone-<versão>.dmg` com atalho para Applications e LEIA-ME de
instalação. A versão vem de `packaging/Info.plist`
(`CFBundleShortVersionString`) — bump manual a cada release.

- Assinatura **ad hoc** com hardened runtime: em outro Mac, a primeira
  abertura exige clique-direito → Abrir (Gatekeeper). Developer ID +
  notarização eliminam isso no Ciclo 12.
- O `.app` é autossuficiente: o bundle de recursos white label vai em
  `Contents/Resources` (o `BrandLoader` resolve de lá — nunca depender do
  `.build` da máquina de dev; bug corrigido em 2026-07-03).
- Prompt do Keychain a cada rebuild ad hoc é esperado (identidade muda);
  "Sempre Permitir" resolve até a assinatura definitiva.
- Distribuição para o time: anexar o `.dmg` num **GitHub Release** (binário
  não entra no histórico do git).

## Builds white label

Cada marca deve poder ter:

- Display name.
- Bundle identifier.
- App icon.
- Logo.
- Brand config.
- Endpoints.

Exemplo:

```text
br.com.flux.softphone
br.com.revenda.softphone
```

## Distribuição inicial

Para MVP/testes internos:

- Build local pelo Xcode.
- DMG ou ZIP assinado quando possível.
- Checklist de instalação.
- Registro manual de conta SIP.

## Distribuição comercial futura

Avaliar:

- Assinatura com Developer ID.
- Notarização Apple.
- Auto-update.
- Canal stable/beta.
- Builds por tenant/revenda.

## Checklist pré-release

- Build limpo.
- Versão atualizada.
- Ícone correto.
- Nome correto.
- Config white label correta.
- Nenhuma credencial hardcoded.
- Logs sanitizados.
- Registro SIP testado.
- Chamada de saída testada.
- Chamada de entrada testada.
- Histórico testado.
- Microfone testado.
- Diagnóstico testado.

## Critério de aceite

Um build só pode ser compartilhado com cliente se não expuser segredo, não usar marca errada e não depender de configuração local do desenvolvedor.
