import Darwin

protocol MemoryRepository: AnyObject {
    var current: MemoryInfo { get }

    init()

    func update()
    func reset()
}

final class MemoryRepositoryImpl: MemoryRepository {
    
    var current = MemoryInfo()
    private let kiloByte: Double = 1_024 // 2^10
    private let gigaByte: Double = 1_073_741_824 // 2^30
    private let hostVmInfo64Count: mach_msg_type_number_t!
    private let hostBasicInfoCount: mach_msg_type_number_t!

    init() {
        hostVmInfo64Count = UInt32(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        hostBasicInfoCount = UInt32(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
    }

    private var maxMemory: Double {
        var size: mach_msg_type_number_t = hostBasicInfoCount
        let hostInfo = host_basic_info_t.allocate(capacity: 1)
        let _ = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int()) { (pointer) -> kern_return_t in
            return host_info(mach_host_self(), HOST_BASIC_INFO, pointer, &size)
        }
        let data = hostInfo.move()
        hostInfo.deallocate()
        return Double(data.max_mem) / gigaByte
    }

    private var vmStatistics64: vm_statistics64 {
        var size: mach_msg_type_number_t = hostVmInfo64Count
        let hostInfo = vm_statistics64_t.allocate(capacity: 1)
        let _ = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { (pointer) -> kern_return_t in
            return host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &size)
        }
        let data = hostInfo.move()
        hostInfo.deallocate()
        return data
    }

    func update() {
        var result = MemoryInfo()

        defer {
            current = result
        }

        let maxMem = maxMemory
        let load = vmStatistics64

        let unit        = Double(vm_kernel_page_size) / kiloByte
        let active      = Double(load.active_count) * unit
        let speculative = Double(load.speculative_count) * unit
        let inactive    = Double(load.inactive_count) * unit
        let wired       = Double(load.wire_count) * unit
        let compressed  = Double(load.compressor_page_count) * unit
        let purgeable   = Double(load.purgeable_count) * unit
        let external    = Double(load.external_page_count) * unit
        let using       = active + inactive + speculative + wired + compressed - purgeable - external

        result.value = min(99.9, (100.0 * using / maxMem))
        result.setPressureValue((100.0 * (wired + compressed) / maxMem))
        result.setAppValue((using - wired - compressed))
        result.setWiredValue(wired)
        result.setCompressedValue(compressed)
    }

    func reset() {
        current = MemoryInfo()
    }
}

final class MemoryRepositoryMock: MemoryRepository {
    let current = MemoryInfo()
    func update() {}
    func reset() {}
}
