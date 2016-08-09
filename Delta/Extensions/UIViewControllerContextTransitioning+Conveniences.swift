//
//  UIViewControllerContextTransitioning+Conveniences.swift
//  Delta
//
//  Created by Riley Testut on 7/28/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import UIKit

extension UIViewControllerContextTransitioning
{
    /// UIViewControllers
    var sourceViewController: UIViewController {
        return self.viewController(forKey: UITransitionContextFromViewControllerKey)!
    }
    
    var destinationViewController: UIViewController {
        return self.viewController(forKey: UITransitionContextToViewControllerKey)!
    }
    
    /// UIViews
    var sourceView: UIView {
        return self.sourceViewController.view
    }
    
    var destinationView: UIView {
        return self.destinationViewController.view
    }
    
    
    /// Frames
    var sourceViewInitialFrame: CGRect? {
        let frame = self.initialFrame(for: self.sourceViewController)
        return frame.isEmpty ? nil : frame
    }
    
    var sourceViewFinalFrame: CGRect? {
        let frame = self.finalFrame(for: self.sourceViewController)
        return frame.isEmpty ? nil : frame
    }
    
    var destinationViewInitialFrame: CGRect? {
        let frame = self.initialFrame(for: self.destinationViewController)
        return frame.isEmpty ? nil : frame
    }
    
    var destinationViewFinalFrame: CGRect? {
        let frame = self.finalFrame(for: self.destinationViewController)
        return frame.isEmpty ? nil : frame
    }
}
