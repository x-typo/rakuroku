import SwiftUI

struct FilterSheet: View {
    let title: String
    let filters: [String]
    @Binding var selectedFilter: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 20)
                .padding(.bottom, 20)

            ForEach(filters, id: \.self) { filter in
                Button {
                    selectedFilter = filter
                    dismiss()
                } label: {
                    Text(filter)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fontWeight(selectedFilter == filter ? .bold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(selectedFilter == filter ? Theme.primary : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
