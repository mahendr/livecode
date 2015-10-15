/* Copyright (C) 2015 LiveCode Ltd.
 
 This file is part of LiveCode.
 
 LiveCode is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License v3 as published by the Free
 Software Foundation.
 
 LiveCode is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or
 FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 for more details.
 
 You should have received a copy of the GNU General Public License
 along with LiveCode.  If not see <http://www.gnu.org/licenses/>.  */

#include "prefix.h"

#include "globdefs.h"
#include "filedefs.h"
#include "objdefs.h"
#include "parsedef.h"

#include "execpt.h"
#include "util.h"
#include "mcerror.h"
#include "sellst.h"
#include "stack.h"
#include "card.h"
#include "image.h"
#include "widget.h"
#include "param.h"
#include "osspec.h"
#include "cmds.h"
#include "scriptpt.h"
#include "hndlrlst.h"
#include "debug.h"
#include "redraw.h"
#include "font.h"
#include "chunk.h"
#include "graphicscontext.h"
#include "objptr.h"

#include "globals.h"
#include "context.h"

#include "native-layer-ios.h"

#include "platform.h"
#include "platform-internal.h"

#include "mbliphoneapp.h"
#include "mblcontrol.h"

#include "graphics_util.h"

MCNativeLayerIOS::MCNativeLayerIOS(MCWidgetRef p_widget, UIView *p_native_view) :
  m_widget(p_widget),
  m_view([p_native_view retain])
{
    ;
}

MCNativeLayerIOS::~MCNativeLayerIOS()
{
    if (m_view != nil)
    {
        doDetach();
        MCIPhoneRunBlockOnMainFiber(^{[m_view release];});
    }
}

void MCNativeLayerIOS::OnToolChanged(Tool p_new_tool)
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
	
	OnVisibilityChanged(ShouldShowWidget(t_widget));
	t_widget->Redraw();
}

void MCNativeLayerIOS::OnOpen()
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
    
    // Unhide the widget, if required
    if (isAttached() && t_widget->getopened() == 1)
        doAttach();
}

void MCNativeLayerIOS::OnClose()
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
    
    if (isAttached() && t_widget->getopened() == 1)
        doDetach();
}

#import <UIKit/UIButton.h>

void MCNativeLayerIOS::OnAttach()
{
    m_attached = true;
    doAttach();
}

void MCNativeLayerIOS::doAttach()
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
    
    // Act as if there was a re-layer to put the widget in the right place
    doRelayer();
    
	OnVisibilityChanged(ShouldShowWidget(t_widget));
}

void MCNativeLayerIOS::OnDetach()
{
    m_attached = false;
    doDetach();
}

void MCNativeLayerIOS::doDetach()
{
    // Remove the view from the stack's content view
    MCIPhoneRunBlockOnMainFiber(^{
        [m_view removeFromSuperview];
    });
}

void MCNativeLayerIOS::OnPaint(MCGContextRef)
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
    
    // If the widget is not in edit mode, we trust it to paint itself
    if (t_widget->isInRunMode())
        return;
    
    // Edit mode is not supported on iOS
    return;
}

void MCNativeLayerIOS::OnGeometryChanged(const MCRectangle& p_old_rect)
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
    
    doSetRect(t_widget->getrect());
}

void MCNativeLayerIOS::doSetRect(const MCRectangle& p_rect)
{
    CGRect t_nsrect;
    MCGRectangle t_xformed;
    t_xformed = MCNativeControlUserRectToDeviceRect(MCGRectangleMake(p_rect.x, p_rect.y, p_rect.width, p_rect.height));
    t_nsrect = CGRectMake(t_xformed.origin.x, t_xformed.origin.y, t_xformed.size.width, t_xformed.size.height);
    
    MCIPhoneRunBlockOnMainFiber(^{
        [m_view setFrame:t_nsrect];
        [m_view setNeedsDisplay];
    });
}

void MCNativeLayerIOS::OnVisibilityChanged(bool p_visible)
{
    MCIPhoneRunBlockOnMainFiber(^{
        [m_view setHidden:p_visible ? NO : YES];
    });
	if (p_visible)
		OnGeometryChanged(MCRectangleMake(0,0,0,0));
}

void MCNativeLayerIOS::OnLayerChanged()
{
    doRelayer();
}

void MCNativeLayerIOS::doRelayer()
{
    MCWidget* t_widget = MCWidgetGetHost(m_widget);
    
    // Find which native layer this should be inserted below
    MCWidget* t_before;
    MCNativeLayerIOS *t_before_layer = nil;
    t_before = findNextLayerAbove(t_widget);
    if (t_before != nil)
    {
        t_before_layer = reinterpret_cast<MCNativeLayerIOS*>(t_before->getNativeLayer());
    }
    
    UIView *t_view;
    t_view = getMainView();
    
    // Insert the widget in the correct place (but only if the card is current)
    if (isAttached() && t_widget->getstack()->getcard() == t_widget->getstack()->getcurcard())
    {
        MCIPhoneRunBlockOnMainFiber(^{
            [m_view removeFromSuperview];
            if (t_before_layer != nil)
            {
                // There is another native layer above this one
                [t_view insertSubview:m_view belowSubview:t_before_layer->m_view];
            }
            else
            {
                // This is the top-most native layer
                [t_view addSubview:m_view];
            }
            [t_view setNeedsDisplay];
        });
    }
}

UIView* MCNativeLayerIOS::getMainView()
{
    return MCIPhoneGetView();
}

bool MCNativeLayerIOS::GetNativeView(void *&r_view)
{
	if (m_view == nil)
		return false;
	
	r_view = m_view;
	return true;
}

////////////////////////////////////////////////////////////////////////////////

MCNativeLayer *MCNativeLayer::CreateNativeLayer(MCWidgetRef p_widget, void *p_native_view)
{
	return new MCNativeLayerIOS(p_widget, (UIView*)p_native_view);
}

////////////////////////////////////////////////////////////////////////////////
