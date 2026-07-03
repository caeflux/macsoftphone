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

### Implementado (2026-07-03): controle de codec G.711

- `AudioCodecPreference` (FluxDomain) + `MediaPreferences` persistidas em
  UserDefaults (`UserDefaultsMediaPreferencesStore`), editáveis em
  Ajustes → Áudio. Padrão: PCMA primeiro (mercado brasileiro).
- Oferta SDP: `G711Codec.offerOrder(preferring:)` — o preferido primeiro,
  ambos sempre ofertados (interoperabilidade).
- Resposta/re-INVITE: `RemoteMedia.negotiatedCodec(preferring:)` — escolhe o
  NOSSO preferido quando o remoto o oferece; senão, a ordem do remoto.
- As preferências são lidas a cada negociação (closure injetada no
  `NativeSIPClient`) — mudanças valem para a próxima chamada, nunca para a
  chamada em andamento.
- Codecs futuros (Opus/G.722) entram por `AudioCodecPreference` + encoder no
  `RTPMediaSession` sem tocar na UI.

## Processamento de voz (2026-07-03)

Cancelamento de eco acústico (AEC) e supressão de ruído via **Voice
Processing I/O** da Apple (`setVoiceProcessingEnabled` na entrada E na saída
do `AVAudioEngine` — o AEC referencia o áudio reproduzido pelo próprio
engine). AGC é flag separada (`isVoiceProcessingAGCEnabled`).

- Configurável por `AudioProcessingOptions` na criação do `RTPMediaSession`
  (por chamada, via `mediaFactory` na composição). Padrão: DESLIGADO —
  opt-in nos Ajustes. (Era ligado por padrão; teste de campo em 2026-07-03
  teve chamada MUDA — ver incidente em docs/10. Religa por padrão só depois
  de validado em campo.)
- Habilitado ANTES de ler formatos/instalar taps — o VPIO troca a unidade de
  I/O e os formatos mudam; o conversor de 8 kHz absorve qualquer taxa.
- Falha ao habilitar NÃO derruba a chamada nem segue meio-configurada: o
  engine com VP é descartado INTEIRO e um engine limpo (caminho V1) é
  reconstruído. Entrada VPIO + saída normal = mudez — nunca deixar híbrido.
- O start do engine loga modo + formato de entrada em `AppLog.audio` —
  evidência para depurar áudio em campo.
- AEC+NS são um recurso único do sistema — a UI expõe um só toggle para os
  dois, mais o toggle de AGC (honestidade sobre o que o sistema oferece).

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
