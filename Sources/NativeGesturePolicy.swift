import Foundation

// Pure gesture decisions, shared by the native navigation and spotlight.
// No provider/account writes, device identity or animation state belongs here.
enum NativeGesturePolicy {
    static func tabProgress(x: Double,width: Double,count: Int,inset: Double = 8) -> Double {
        guard count > 1,width.isFinite,x.isFinite,width > inset*2 else { return 0 }
        let cell = (width-inset*2)/Double(count)
        return min(Double(count-1),max(0,(x-inset)/cell-0.5))
    }
    static func tabIndex(x: Double,width: Double,count: Int) -> Int {
        Int(tabProgress(x:x,width:width,count:count).rounded())
    }
    static func pageDelta(horizontal: Double,vertical: Double,threshold: Double = 45) -> Int {
        guard horizontal.isFinite,vertical.isFinite,abs(horizontal) >= threshold,abs(horizontal) > abs(vertical)*1.2 else { return 0 }
        return horizontal < 0 ? 1 : -1
    }
}
