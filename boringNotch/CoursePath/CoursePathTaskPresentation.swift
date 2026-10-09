import Foundation

enum CoursePathTaskPresentation {
    static func sorted(_ tasks: [CoursePathTask]) -> [CoursePathTask] {
        tasks.sorted {
            if $0.completed != $1.completed { return !$0.completed }
            return $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
    }
    static func minutes(_ task: CoursePathTask) -> Double {
        task.minutes.isFinite && task.minutes > 0 ? task.minutes : 0
    }
    static func duration(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "0 min" }
        let hours = (minutes / 60).rounded(.down), remainder = minutes.truncatingRemainder(dividingBy: 60)
        let hoursLabel = hours.formatted(.number.precision(.fractionLength(0)))
        let minutesLabel = remainder.formatted(.number.precision(.fractionLength(0...1)))
        return hours > 0 ? (remainder > 0 ? "\(hoursLabel)h \(minutesLabel)m" : "\(hoursLabel)h") : "\(minutesLabel) min"
    }
}
