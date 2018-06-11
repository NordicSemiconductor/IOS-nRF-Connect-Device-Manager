/*
 * Copyright (c) 2017-2018 Runtime Inc.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation

public protocol McuMgrTransport {
    func getScheme() -> McuMgrScheme
    func send<T: McuMgrResponse>(data: Data, callback: @escaping McuMgrCallback<T>)
}
