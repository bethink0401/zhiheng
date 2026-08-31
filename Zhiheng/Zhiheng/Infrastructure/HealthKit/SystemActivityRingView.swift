import HealthKit
import HealthKitUI
import SwiftUI

/// Apple's official Move, Exercise, and Stand ring, fed only normalized
/// domain progress so the Today feature doesn't depend on HealthKit UI types.
struct SystemActivityRingView: UIViewRepresentable {
    let progress: TodayActivityRingProgress
    var animated = false

    func makeUIView(context: Context) -> HKActivityRingView {
        let view = HKActivityRingView()
        view.backgroundColor = .black
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: HKActivityRingView, context: Context) {
        uiView.setActivitySummary(makeSummary(), animated: animated)
    }

    private func makeSummary() -> HKActivitySummary {
        let summary = HKActivitySummary()
        summary.activityMoveMode = .activeEnergy
        let goal = 100.0

        summary.activeEnergyBurned = HKQuantity(
            unit: .kilocalorie(),
            doubleValue: normalized(progress.activeEnergy) * goal
        )
        summary.activeEnergyBurnedGoal = HKQuantity(unit: .kilocalorie(), doubleValue: goal)
        summary.appleExerciseTime = HKQuantity(
            unit: .minute(),
            doubleValue: normalized(progress.exercise) * goal
        )
        summary.exerciseTimeGoal = HKQuantity(unit: .minute(), doubleValue: goal)
        summary.appleStandHours = HKQuantity(
            unit: .count(),
            doubleValue: normalized(progress.stand) * goal
        )
        summary.standHoursGoal = HKQuantity(unit: .count(), doubleValue: goal)
        return summary
    }

    private func normalized(_ value: Double?) -> Double {
        min(max(value ?? 0, 0), 1)
    }
}
