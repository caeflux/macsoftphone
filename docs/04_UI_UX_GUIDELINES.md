# 04 — Diretrizes de UI/UX

## Direção visual

O softphone deve transmitir:

- Confiança.
- Robustez.
- Clareza.
- Operação profissional.
- Simplicidade corporativa.

Evitar:

- Visual amador.
- Excesso de gradientes.
- Botões com aparência genérica demais.
- Poluição visual.
- Ícones sem consistência.
- Layout inspirado em softphones antigos demais.

## Estrutura principal

Telas recomendadas:

1. Onboarding / Login
2. Status de Conta
3. Discador
4. Chamada Ativa
5. Histórico
6. Contatos
7. Configurações
8. Diagnóstico/Suporte

## Janela principal

A janela deve funcionar bem em:

- Tamanho compacto.
- Uso lateral no monitor.
- Tela cheia, sem parecer esticada.
- Modo claro e escuro, se implementado.

## Layout sugerido

```text
┌──────────────────────────────────────┐
│ Header: Logo + Status SIP + Perfil   │
├───────────────┬──────────────────────┤
│ Sidebar       │ Área principal       │
│ - Discador    │                      │
│ - Histórico   │                      │
│ - Contatos    │                      │
│ - Ajustes     │                      │
└───────────────┴──────────────────────┘
```

## Estados visuais obrigatórios

### Registro

- Registrando.
- Registrado.
- Desconectado.
- Erro de autenticação.
- Erro de rede.

### Chamada

- Entrada recebida.
- Discando.
- Chamando.
- Em chamada.
- Em espera.
- Encerrando.
- Chamada encerrada.
- Falha.

## Discador

O discador deve conter:

- Campo de número/destino.
- Teclado numérico.
- Botão chamar.
- Atalho para apagar.
- Suporte a colar número.
- Normalização básica de número, sem destruir ramais ou códigos.

## Tela de chamada ativa

Deve mostrar:

- Número ou contato.
- Estado da chamada.
- Duração.
- Botão encerrar.
- Mute.
- Teclado DTMF.
- Hold, quando implementado.
- Transferência, quando implementada.
- Dispositivo de áudio atual.

## Histórico

Lista com:

- Nome/número.
- Direção.
- Data/hora.
- Duração.
- Status.
- Ação rápida para ligar novamente.

## Configurações

Separar em grupos:

- Conta SIP.
- Áudio.
- Aparência/marca, apenas se aplicável.
- Diagnóstico.
- Sobre o aplicativo.

## Diagnóstico

A tela de diagnóstico deve ajudar suporte e implantação:

- Status do registro.
- Usuário SIP mascarado.
- Domínio SIP.
- Transporte.
- Último erro.
- Permissão de microfone.
- Dispositivo de entrada.
- Dispositivo de saída.
- Versão do app.
- Botão copiar diagnóstico sem segredos.

## Microcopy

Use mensagens claras:

- “Conta registrada”
- “Falha de autenticação. Verifique usuário e senha.”
- “Não foi possível conectar ao servidor SIP.”
- “Permissão de microfone necessária para chamadas.”
- “Chamada encerrada.”

Evite mensagens técnicas para o usuário final, como:

- “SIP 403” sem explicação.
- “Transport exception”.
- “INVITE failed”.

Essas informações podem aparecer em diagnóstico técnico, não na UI principal.

## Acessibilidade

- Botões com labels claros.
- Contraste adequado.
- Navegação por teclado sempre que possível.
- Estados visuais não dependentes apenas de cor.

## Critério de aceite visual

O app deve parecer adequado para ser apresentado a um cliente empresarial da Flux, sem constrangimento visual, mesmo antes das integrações avançadas.
