# 07 — Testing e QA

## Objetivo

Garantir que o softphone seja estável, confiável e seguro o suficiente para uso corporativo.

## Tipos de teste

### Unitários

Testar:

- Normalização de número.
- Estados de chamada.
- Estados de registro.
- Salvamento/carregamento de configuração.
- Sanitização de logs.
- Feature flags.
- Brand config.

### Integração

Testar:

- Registro SIP contra ambiente de teste.
- Chamada de saída.
- Chamada de entrada.
- Troca de dispositivo de áudio.
- Persistência segura.

### UI

Testar:

- Login manual.
- Tela de discador.
- Chamada ativa.
- Histórico.
- Configurações.
- Erros comuns.

## Cenários mínimos de QA manual

### Registro

- Conta válida registra.
- Senha errada mostra erro claro.
- Domínio inválido mostra erro de conexão.
- Sem internet mostra erro claro.
- Reabrir app mantém conta salva com segurança.

### Chamada de saída

- Ligar para número válido.
- Encerrar antes de atender.
- Encerrar durante chamada ativa.
- Mute durante chamada.
- DTMF durante chamada, quando implementado.

### Chamada de entrada

- Receber chamada com app aberto.
- Atender.
- Rejeitar.
- Encerrar.
- Chamada perdida aparece no histórico.

### Áudio

- Selecionar microfone.
- Selecionar saída.
- Bloquear permissão de microfone e verificar mensagem.
- Trocar dispositivo durante uso.

### White label

- Alterar nome do app por configuração.
- Alterar logo.
- Alterar cor primária.
- Alterar domínio SIP padrão.
- Confirmar que não há texto Flux hardcoded em build customizado.

## Teste de regressão obrigatório

Antes de considerar qualquer ciclo pronto, verificar:

- Build compila.
- Registro SIP não foi quebrado.
- Discador abre.
- Chamada não sofreu regressão.
- Histórico não perdeu dados sem necessidade.
- Credenciais continuam seguras.

## Logs de QA

Ao testar chamadas, registrar:

- Data/hora.
- Rede usada.
- Conta/ramal mascarado.
- Destino mascarado.
- Resultado.
- Erro visível.
- Versão/build do app.

## Critério de aceite mínimo do MVP

O MVP só pode ser considerado validado quando:

- Registra conta real.
- Faz chamada real com áudio bidirecional.
- Recebe chamada real.
- Permite encerrar e mutar.
- Salva credenciais no Keychain.
- Gera build instalável para teste.
