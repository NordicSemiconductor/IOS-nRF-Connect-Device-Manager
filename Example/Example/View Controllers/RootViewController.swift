/*
* Copyright (c) 2018 Nordic Semiconductor ASA.
*
* SPDX-License-Identifier: Apache-2.0
*/

import UIKit

class RootViewController: UINavigationController {
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithOpaqueBackground()
            navBarAppearance.backgroundColor = UIColor.dynamicColor(light: .nordic, dark: .black)
            navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            navigationBar.standardAppearance = navBarAppearance
            navigationBar.scrollEdgeAppearance = navBarAppearance
        } else {
            // Fallback on earlier versions
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let introShown = UserDefaults.standard.bool(forKey: "introShown")
        if !introShown {
            UserDefaults.standard.set(true, forKey: "introShown")
            showIntro(animated: false)
        }
    }
    
    func showIntro(animated: Bool) {
        if let intro = storyboard?.instantiateViewController(withIdentifier: "intro") {
            intro.modalPresentationStyle = .fullScreen
            present(intro, animated: animated)
        }
    }
}
