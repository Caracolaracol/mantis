import SwiftUI

struct AudioInputPicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Micrófono o interfaz", selection: $model.selectedAudioInputUID) {
                    Text("Predeterminada de macOS").tag("")
                    if !model.selectedAudioInputUID.isEmpty,
                       !model.audioInputs.contains(where: { $0.id == model.selectedAudioInputUID }) {
                        Text("Entrada desconectada").tag(model.selectedAudioInputUID)
                    }
                    ForEach(model.audioInputs) { device in
                        Text("\(device.name) · \(device.channelCount) canales").tag(device.id)
                    }
                }
                Button("Actualizar", action: model.refreshAudioInputs)
            }
            if let device = model.audioInputs.first(where: { $0.id == model.selectedAudioInputUID }) {
                ScrollView(.horizontal) {
                    HStack {
                        Text("Canales:").font(.caption)
                        ForEach(0..<device.channelCount, id: \.self) { channel in
                            Toggle("\(channel + 1)", isOn: Binding(
                                get: { model.selectedInputChannels.contains(channel) },
                                set: { enabled in
                                    model.setInputChannel(channel, enabled: enabled)
                                })).toggleStyle(.checkbox).font(.caption)
                                .disabled(model.selectedInputChannels.count == 1 && model.selectedInputChannels.contains(channel))
                        }
                    }.padding(.vertical, 2)
                }
                Text("Solo se guardan los canales marcados, mezclados a mono. «Todo» incluye computador + entrada, no todos los canales de la interfaz.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
                Text("Puedes marcar ambos canales. Debe quedar al menos uno seleccionado.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            } else {
                Text("Usa la entrada de Ajustes del Sistema → Sonido → Entrada. Para elegir canales específicos, selecciona tu interfaz aquí.")
                    .font(.caption).foregroundStyle(MantisTheme.secondary)
            }
        }.disabled(model.busy)
    }
}
