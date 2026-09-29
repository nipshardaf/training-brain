import Foundation
import HealthKit

// Records the session as a Strength workout in Apple Health (heart rate and
// calories included) and reports live heart rate.
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    var onHeartRate: ((Double) -> Void)?

    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let hr = HKObjectType.quantityType(forIdentifier: .heartRate),
              let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), energy]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), hr, energy]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start() {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    func end(save: Bool) {
        guard let s = session, let b = builder else { return }
        session = nil
        builder = nil
        s.end()
        b.endCollection(withEnd: Date()) { _, _ in
            if save {
                b.finishWorkout { _, _ in }
            } else {
                b.discardWorkout()
            }
        }
    }

    // MARK: HKWorkoutSessionDelegate
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    // MARK: HKLiveWorkoutBuilderDelegate
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hr = HKObjectType.quantityType(forIdentifier: .heartRate), collectedTypes.contains(hr),
              let q = workoutBuilder.statistics(for: hr)?.mostRecentQuantity() else { return }
        let bpm = q.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        DispatchQueue.main.async { self.onHeartRate?(bpm) }
    }
}
