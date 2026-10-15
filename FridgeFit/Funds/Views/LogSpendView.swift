import SwiftUI

// screen 2 - log a grocery spend against the budget. on save, shows either a plain
// confirmation, a supportive over-budget warning, or a validation error - but a
// spend that pushes the user over budget still gets recorded either way.
struct LogSpendView: View {
    @State private var viewModel: LogSpendViewModel

    init(environment: FundsEnvironment) {
        _viewModel = State(initialValue: LogSpendViewModel(environment: environment))
    }

    var body: some View {
        @Bindable var vm = viewModel

        Form {
            Section("Purchase") {
                HStack {
                    Text(vm.currency.symbol)
                        .foregroundStyle(.secondary)
                    TextField("Amount", text: $vm.amountText)
                        .keyboardType(.decimalPad)
                }
                TextField("Store (optional)", text: $vm.storeName)
                DatePicker("Date", selection: $vm.spentOn,
                           in: ...Date(), displayedComponents: .date)
            }

            Section {
                Button {
                    vm.save()
                } label: {
                    Text("Log Spend").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let warning = vm.warningMessage {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else if let error = vm.errorMessage {
                Section {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            } else if vm.didSave {
                Section {
                    Label("Spend logged.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Log a Spend")
    }
}

#Preview {
    NavigationStack {
        LogSpendView(environment: .sample())
    }
}
