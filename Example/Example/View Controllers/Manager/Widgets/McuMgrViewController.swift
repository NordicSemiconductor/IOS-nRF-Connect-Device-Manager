/*
 * Copyright (c) 2018 Nordic Semiconductor ASA.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import UIKit
import iOSMcuManagerLibrary

protocol McuMgrViewController {

    var transporter: McuMgrTransport! { get set }
}
