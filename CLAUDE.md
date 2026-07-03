# CLAUDE.md — Instruções Centrais para o Claude Code

Você está trabalhando no desenvolvimento de um softphone white label para macOS/MacBook para a Flux.

Este projeto deve ser tratado como produto comercial sério, não como protótipo descartável. Toda alteração deve preservar estabilidade, organização, segurança e capacidade de evolução.

## Missão

Criar um softphone desktop para macOS com:

- Login/provisionamento SIP.
- Registro SIP estável.
- Chamadas de entrada e saída.
- Controle de áudio profissional.
- Histórico de chamadas.
- Contatos locais e/ou integrados futuramente.
- Suporte white label por cliente/revenda/tenant.
- Arquitetura preparada para integração com SBC, PABX multi-tenant, CRM e APIs Flux.

## Stack preferencial

A stack preferencial é:

- macOS nativo.
- Swift + SwiftUI para interface.
- MVVM ou Clean Architecture simplificada.
- Camada SIP isolada atrás de protocolos/interfaces.
- Keychain para credenciais.
- Configuração white label via arquivos declarativos.
- Logs estruturados sem vazamento de senha, token ou dados sensíveis.

Se uma biblioteca SIP externa for usada, ela deve ficar encapsulada em um módulo próprio, sem contaminar a UI ou as regras de negócio.

## Princípios obrigatórios

1. Não misture UI com lógica SIP.
2. Não armazene senha SIP em texto puro.
3. Não hardcode marcas, domínios, cores, logos, tenants ou credenciais.
4. Não implemente atalhos inseguros para “funcionar rápido”.
5. Não quebre fluxo básico de chamada ao mexer em UI.
6. Não crie código monolítico difícil de manter.
7. Não remova funcionalidades existentes sem justificar claramente.
8. Não invente integração com API Flux sem criar camada abstrata e mockável.
9. Sempre prefira código simples, testável e observável.
10. Sempre atualize documentação quando criar ou alterar decisões estruturais.

## Ordem de trabalho em cada ciclo

Em cada execução, siga esta ordem:

1. Leia `README.md`, `CLAUDE.md` e os documentos em `docs/` relevantes para a tarefa.
2. Audite rapidamente o estado atual do projeto.
3. Identifique o menor conjunto de mudanças que entrega valor real.
4. Implemente.
5. Rode build/testes/lint quando disponíveis.
6. Corrija erros encontrados.
7. Atualize documentação se a arquitetura, fluxo ou comportamento mudar.
8. Entregue resumo objetivo com:
   - O que foi alterado.
   - Arquivos principais.
   - Riscos conhecidos.
   - Próximo passo recomendado.

## Prioridade do produto

A prioridade do produto é nesta ordem:

1. Chamadas funcionarem com estabilidade.
2. Registro SIP confiável.
3. Áudio limpo e previsível.
4. Interface clara e profissional.
5. White label sem retrabalho.
6. Integrações Flux.
7. Polimento visual.

## Definição de pronto

Uma etapa só está pronta se:

- Compila sem erro.
- Não quebra funcionalidades anteriores.
- Tem estrutura compreensível.
- Não expõe segredo.
- Tem critério de aceite verificável.
- Tem logs úteis para depuração.

## Tom visual do produto

O app deve parecer uma plataforma de telecom profissional:

- Robusto.
- Confiável.
- Moderno.
- Limpo.
- Corporativo sem ser antiquado.
- White label sem parecer template genérico.

Evite aparência de app amador, clone barato de softphone antigo, excesso de gradientes, excesso de sombras ou layout “startup colorida” demais.
