//
//  LogTapStore.swift
//  LogTapIOS
//
//  Created by Hussein Habibi Juybari on 06.09.25.
//

import Foundation

final class LogTapStore {
  private let capacity: Int
  private var deque: [LogEvent] = []
  private var nextId: Int64 = 1
  private let q = DispatchQueue(label: "logtap.store", qos: .utility)
  private var subscribers: [UUID: (LogEvent) -> Void] = [:]

  init(capacity: Int) { self.capacity = max(100, capacity) }

  func add(_ ev: LogEvent) {
    var e = ev
    e.id = nextId
    nextId += 1
    q.sync {
      if deque.count == capacity { deque.removeFirst() }
      deque.append(e)
      subscribers.values.forEach { $0(e) }
    }
  }

  func clear() {
    q.sync { deque.removeAll(keepingCapacity: true) }
  }

  func snapshot(sinceId: Int64? = nil, limit: Int = 500) -> [LogEvent] {
    q.sync {
      let src = deque
      let filtered = sinceId != nil ? src.filter { $0.id > sinceId! } : src
      return Array(filtered.suffix(limit))
    }
  }

  @discardableResult
  func subscribe(_ block: @escaping (LogEvent) -> Void) -> UUID {
    let id = UUID()
    q.sync { subscribers[id] = block }
    return id
  }

  func unsubscribe(_ id: UUID) {
    q.sync { subscribers.removeValue(forKey: id) }
  }
}
