# 03 — SIP, Áudio e Engine de Chamadas

## Objetivo

Construir uma camada de chamadas estável, isolada da interface e preparada para trocar a implementação SIP se necessário.

## Responsabilidades da camada SIP

- Configurar conta SIP.
- Registrar/desregistrar.
- Monitorar estado de registro.
- Originar chamada.
- Receber chamada.
- Atender, rejeitar e encerrar.
- Enviar DTMF.
- Controlar hold/resume quando implementado.
- Publicar eventos para a aplicação.

## Responsabilidades da camada de áudio

- Listar dispositivos de entrada.
- Listar dispositivos de saída.
- Selecionar microfone.
- Selecionar saída de áudio.
- Controlar mute.
- Identificar falhas de permissão de microfone.
- Monitorar troca de dispositivo.

## Eventos obrigatórios

A engine deve emitir eventos claros:

```swift
enum SIPEvent {
    case registrationChanged(RegistrationState)
    case incomingCall(CallSession)
    case callStateChanged(CallSession)
    case audioRouteChanged
    case error(SIPClientError)
}
```

## Dados da conta SIP

```swift
struct SIPAccount {
    let username: String
    let password: String
    let domain: String
    let displayName: String?
    let authUsername: String?
    let outboundProxy: String?
    let transport: SIPTransport
}
```

## Transportes

Suportar arquitetura para:

- UDP
- TCP
- TLS

O MVP pode começar com o transporte mais simples compatível com o ambiente de testes, mas a arquitetura não deve impedir evolução para TLS.

## NAT e rede

A aplicação deve ser preparada para cenários corporativos:

- Redes com NAT.
- Wi-Fi instável.
- Troca de rede.
- VPN.
- Firewall restritivo.
- DNS com falha.

Sempre que possível, mostrar erro compreensível para o usuário:

- Falha de autenticação.
- Servidor indisponível.
- Sem internet.
- Microfone sem permissão.
- Conta não registrada.

## Codecs

Preparar modelo para codecs, sem acoplar UI à implementação:

- Opus, quando disponível.
- G.711 A-law/u-law para compatibilidade.
- G.729 apenas se houver licença e decisão explícita.

## Estados de chamada

```swift
enum CallState {
    case idle
    case incoming
    case dialing
    case ringing
    case active
    case held
    case ending
    case ended(reason: CallEndReason?)
    case failed(error: CallFailureReason)
}
```

## Histórico de chamadas

Registrar no histórico:

- ID local.
- Número/destino.
- Direção: entrada/saída/perdida.
- Data/hora.
- Duração.
- Status final.
- Conta usada.

Não registrar senha, token, IP sensível ou payload SIP completo no histórico.

## Logs

Logs devem ajudar o suporte, mas não expor segredo.

Permitido:

- Estado de registro.
- Erro de rede genérico.
- Tempo de chamada.
- ID da chamada mascarado.

Não permitido:

- Senha SIP.
- Token.
- Authorization header.
- Payload completo com credenciais.
- Dados pessoais sem necessidade.

## Critérios mínimos do MVP

- Conta registra.
- App mostra status correto.
- Chamada de saída funciona.
- Chamada de entrada é exibida.
- Usuário consegue atender e encerrar.
- Microfone pode ser mutado.
- Histórico registra chamadas.
- Falhas comuns são visíveis e compreensíveis.
