/*
* Copyright (c) 2018 Nordic Semiconductor ASA.
*
* SPDX-License-Identifier: Apache-2.0
*/

import UIKit

// MARK: - RootViewController

final class RootViewController: UINavigationController {
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: viewIsAppearing
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.dynamicColor(light: .nordic, dark: .black)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        navigationBar.standardAppearance = navBarAppearance
        navigationBar.scrollEdgeAppearance = navBarAppearance
    }
    
    // MARK: viewDidAppear
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let introShown = UserDefaults.standard.bool(forKey: "introShown")
        guard !introShown else { return }
        
        UserDefaults.standard.set(true, forKey: "introShown")
        showIntro(animated: false)
    }
    
    // MARK: showIntro
    
    func showIntro(animated: Bool) {
        if let intro = storyboard?.instantiateViewController(withIdentifier: "intro") {
            intro.modalPresentationStyle = .fullScreen
            present(intro, animated: animated)
        }
    }
}
