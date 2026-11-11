import Foundation
import Testing
@testable import Snowdrop

@Suite("Vinyl wallpaper spin policy", .tags(.service))
struct VinylSpinPolicyTests {
    @Test("The record turns only while music plays and the wallpaper can be seen")
    func spinsOnlyWhenPlayingAndVisible() {
        #expect(VinylSpinPolicy.shouldSpin(isPlaying: true, isWindowVisible: true, isDisplayAwake: true, reduceMotion: false))
        #expect(!VinylSpinPolicy.shouldSpin(isPlaying: false, isWindowVisible: true, isDisplayAwake: true, reduceMotion: false))
        #expect(!VinylSpinPolicy.shouldSpin(isPlaying: true, isWindowVisible: false, isDisplayAwake: true, reduceMotion: false))
        #expect(!VinylSpinPolicy.shouldSpin(isPlaying: true, isWindowVisible: true, isDisplayAwake: false, reduceMotion: false))
        #expect(!VinylSpinPolicy.shouldSpin(isPlaying: true, isWindowVisible: true, isDisplayAwake: true, reduceMotion: true))
    }

    @Test("Low Power Mode halves the frame rate")
    func lowPowerLowersFrameRate() {
        #expect(VinylSpinPolicy.framesPerSecond(lowPowerMode: false) == 60)
        #expect(VinylSpinPolicy.framesPerSecond(lowPowerMode: true) == 30)
    }

    @Test("The platter eases up to full speed, clockwise")
    func spinsUp() {
        var dynamics = VinylSpinDynamics()
        dynamics.targetSpeed = VinylSpinDynamics.cruiseSpeed
        for _ in 0 ..< 60 { dynamics.advance(by: 1.0 / 60) }
        // After one second it is mostly there, but still easing in.
        #expect(dynamics.speed > VinylSpinDynamics.cruiseSpeed * 0.8)
        #expect(dynamics.speed < VinylSpinDynamics.cruiseSpeed)
        for _ in 0 ..< 180 { dynamics.advance(by: 1.0 / 60) }
        #expect(abs(dynamics.speed - VinylSpinDynamics.cruiseSpeed) < 0.01)
        #expect(dynamics.angle < 0)
    }

    @Test("Letting go makes the platter coast, slowing down smoothly, and then stop")
    func coastsToAStop() {
        var dynamics = VinylSpinDynamics()
        dynamics.speed = VinylSpinDynamics.cruiseSpeed
        dynamics.targetSpeed = VinylSpinDynamics.cruiseSpeed
        dynamics.targetSpeed = 0
        var previous = dynamics.speed
        var seconds = 0.0
        while dynamics.isMoving, seconds < 20 {
            dynamics.advance(by: 1.0 / 60)
            seconds += 1.0 / 60
            #expect(dynamics.speed <= previous)
            previous = dynamics.speed
        }
        #expect(!dynamics.isMoving)
        #expect(seconds > 2 && seconds < 8)
    }

    @Test("One turn takes 1.8 seconds, 33 1/3 rpm")
    func turnsAtThirtyThreeRpm() {
        #expect(abs(60 / VinylSpinPolicy.secondsPerTurn - 100.0 / 3) < 0.001)
    }

    @Test("The needle rests off the record and lands in the grooves when playing")
    func needleGeometry() {
        let center = VinylDesk.recordCenter
        func distance(_ angle: Double) -> CGFloat {
            let point = VinylDesk.needle(atAngle: angle)
            return hypot(point.x - center.x, point.y - center.y)
        }
        #expect(distance(VinylDesk.armRestAngle) > VinylDesk.recordRadius + 20)
        let playing = distance(VinylDesk.armPlayAngle)
        #expect(playing > VinylDesk.labelRadius + 20)
        #expect(playing < VinylDesk.recordRadius - 20)
    }

    @Test("The tonearm eases between rest and the record without overshooting")
    func armEasesBetweenEnds() {
        var motion = VinylArmMotion()
        motion.move(toPlaying: true, animated: true)
        var previous = motion.pose
        var steps = 0
        while motion.isMoving, steps < 1000 {
            motion.advance(by: 1.0 / 60)
            #expect(motion.pose >= previous)
            #expect(motion.pose <= 1)
            previous = motion.pose
            steps += 1
        }
        #expect(motion.pose == 1)
        #expect(Double(steps) / 60 > 1.5 && Double(steps) / 60 < 2.0)
        motion.move(toPlaying: false, animated: false)
        #expect(motion.pose == 0)
    }

    @Test("Night crosses midnight: 22:00 to 07:00")
    func nightCrossesMidnight() throws {
        let calendar = Calendar(identifier: .gregorian)
        let schedule = VinylDaySchedule(nightStart: 22 * 60, nightEnd: 7 * 60)
        func at(_ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour, minute: minute)))
        }
        #expect(try schedule.isNight(at: at(22), calendar: calendar))
        #expect(try schedule.isNight(at: at(23, 59), calendar: calendar))
        #expect(try schedule.isNight(at: at(3), calendar: calendar))
        #expect(try !schedule.isNight(at: at(7), calendar: calendar))
        #expect(try !schedule.isNight(at: at(12), calendar: calendar))
        #expect(try !schedule.isNight(at: at(21, 59), calendar: calendar))
    }

    @Test("The next change is the coming dusk by day and the coming dawn by night")
    func nextChange() throws {
        let calendar = Calendar(identifier: .gregorian)
        let schedule = VinylDaySchedule(nightStart: 22 * 60, nightEnd: 7 * 60)
        let noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12)))
        let dusk = try #require(schedule.nextChange(after: noon, calendar: calendar))
        #expect(calendar.component(.hour, from: dusk) == 22)
        #expect(calendar.isDate(dusk, inSameDayAs: noon))
        let late = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 23)))
        let dawn = try #require(schedule.nextChange(after: late, calendar: calendar))
        #expect(calendar.component(.hour, from: dawn) == 7)
        #expect(!calendar.isDate(dawn, inSameDayAs: late))
    }

    @Test("Equal start and end times never switch")
    func equalTimesNeverSwitch() {
        let schedule = VinylDaySchedule(nightStart: 600, nightEnd: 600)
        #expect(!schedule.isNight(at: Date()))
        #expect(schedule.nextChange(after: Date()) == nil)
    }
}
