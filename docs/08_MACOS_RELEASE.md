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
