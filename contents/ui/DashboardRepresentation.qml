/***************************************************************************
 *   Copyright (C) 2015 by Eike Hein <hein@kde.org>                        *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA .        *
 ***************************************************************************/

import QtQuick 2.4
import QtGraphicalEffects 1.0

import org.kde.plasma.core 2.1 as PlasmaCore
import org.kde.plasma.components 2.0 as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kquickcontrolsaddons 2.0
import org.kde.kwindowsystem 1.0
import QtQuick.Controls 2.5
import org.kde.plasma.private.shell 2.0

import org.kde.plasma.private.kicker 0.1 as Kicker

import "code/tools.js" as Tools

/* TODO
 * Reverse middleRow layout + keyboard nav + filter list text alignment in rtl locales.
 * Keep cursor column when arrow'ing down past non-full trailing rows into a lower grid.
 * Make DND transitions cleaner by performing an item swap instead of index reinsertion.
*/

Kicker.DashboardWindow {
    id: root

    property bool smallScreen: ((Math.floor(width / units.iconSizes.huge) <= 22) || (Math.floor(height / units.iconSizes.huge) <= 14))

    property int iconSize: smallScreen ? units.iconSizes.large : units.iconSizes.huge
    property int cellSize: iconSize + theme.mSize(theme.defaultFont).height
        + (2 * units.smallSpacing)
        + (2 * Math.max(highlightItemSvg.margins.top + highlightItemSvg.margins.bottom,
                        highlightItemSvg.margins.left + highlightItemSvg.margins.right))
    property int columns: Math.floor(((smallScreen ? 85 : 80)/100) * Math.ceil(width / cellSize))
    property bool searching: (searchField.text != "")

    property bool showFilterList: plasmoid.configuration.showFilterList

    keyEventProxy: searchField
    backgroundColor: Qt.rgba(0, 0, 0, 0.737)

    onKeyEscapePressed: {
        if (searching) {
            searchField.clear();
        } else {
            root.toggle();
        }
    }

    onVisibleChanged: {
        reset();

        if (visible) {
            preloadAllAppsTimer.restart();
        }
    }

    onSearchingChanged: {
        if (!searching) {
            reset();
        } else {
            filterList.currentIndex = -1;

        }
    }

    function reset() {
        searchField.clear();
        filterList.currentIndex = 0;
        funnelModel.sourceModel = rootModel.modelForRow(0);
        mainGrid.model = funnelModel;
        mainGrid.currentIndex = -1;
        filterListScrollArea.focus = showFilterList;
        filterList.model = rootModel;
        mainColumn.tryActivate(0, 0);
    }



    mainItem: MouseArea {
        id: rootItem

        anchors.fill: parent

        acceptedButtons: Qt.LeftButton | Qt.RightButton
        
        LayoutMirroring.enabled: Qt.application.layoutDirection == Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        Connections {
            target: kicker

            onReset: {
                if (!searching) {
                    filterList.applyFilter();

                    funnelModel.reset();
                }
            }

            onDragSourceChanged: {
                if (!dragSource) {
                    // FIXME TODO HACK: Reset all views post-DND to work around
                    // mouse grab bug despite QQuickWindow::mouseGrabberItem==0x0.
                    // Needs a more involved hunt through Qt Quick sources later since
                    // it's not happening with near-identical code in the menu repr.
                    rootModel.refresh();
                }
            }
        }

        KWindowSystem {
            id: kwindowsystem
        }


        Connections {
            target: plasmoid
            onUserConfiguringChanged: {
                if (plasmoid.userConfiguring) {
                    root.hide()
                }
            }
        }

        PlasmaComponents.Menu {
            id: contextMenu

            PlasmaComponents.MenuItem {
                action: plasmoid.action("configure")
            }
        }

        PlasmaExtras.Heading {
            id: dummyHeading

            visible: false

            width: 0

            level: 1
        }

        TextMetrics {
            id: headingMetrics

            font: filterListLabel.font
        }

        Kicker.FunnelModel {
            id: funnelModel

            onSourceModelChanged: {
                if (mainColumn.visible) {
                    mainGrid.currentIndex = -1;
                    mainGrid.forceLayout();
                }
            }
        }

        Timer {
            id: preloadAllAppsTimer

            property bool done: false

            interval: 1000
            repeat: false

            onTriggered: {
                if (done || searching) {
                    return;
                }

                for (var i = 0; i < rootModel.count; ++i) {
                    var model = rootModel.modelForRow(i);

                    if (model.description == "KICKER_ALL_MODEL") {
                        allAppsGrid.model = model;
                        done = true;
                        break;
                    }
                }
            }

            function defer() {
                if (running && !done) {
                    restart();
                }
            }
        }

        Kicker.ContainmentInterface {
            id: containmentInterface
        }

        TextEdit {
            id: searchField

            width: 0
            height: 0

            visible: false

            persistentSelection: true

            onTextChanged: {
                    runnerModel.query = searchField.text;
            }

            function clear() {
                text = "";
            }

            onSelectionStartChanged: Qt.callLater(searchHeading.updateSelection)
            onSelectionEndChanged: Qt.callLater(searchHeading.updateSelection)
        }

        TextEdit {
            id: searchHeading

            anchors {
                horizontalCenter: parent.horizontalCenter
            }

            y: (middleRow.anchors.topMargin / 2) - (smallScreen ? (height/10) : 0)

            font.pointSize: dummyHeading.font.pointSize * 1
            wrapMode: Text.NoWrap
            opacity: 1.0

            selectByMouse: false
            cursorVisible: false

            color: "white"

            text: searching ? i18n("Searching for '%1'", searchField.text) : i18n("Type to search.")

            function updateSelection() {
                if (!searchField.selectedText) {
                    return;
                }

                var delta = text.lastIndexOf(searchField.text, text.length - 2);
                searchHeading.select(searchField.selectionStart + delta, searchField.selectionEnd + delta);
            }
        }

        PlasmaComponents.ToolButton {
            id: cancelSearchButton

            anchors {
                left: searchHeading.right
                leftMargin: units.largeSpacing
                verticalCenter: searchHeading.verticalCenter
            }

            width: units.iconSizes.large
            height: width

            visible: (searchField.text != "")

            iconName: "edit-clear"
            flat: true

            onClicked: searchField.clear();

            Keys.onPressed: {
                if (event.key == Qt.Key_Tab) {
                    event.accepted = true;

                    if (runnerModel.count) {
                        mainColumn.tryActivate(0, 0);
                    } 
                } else if (event.key == Qt.Key_Backtab) {
                    event.accepted = true;
                }
            }
        }

        Row {
            id: middleRow

            anchors {
                top: parent.top
                topMargin: units.gridUnit * (smallScreen ? 8: 10)
                bottom: parent.bottom
                bottomMargin: (units.gridUnit * 2)
                horizontalCenter: parent.horizontalCenter
            }


            //@todo why this?
            //width: parent.width

            spacing: units.gridUnit * 2

            Item {
                id: mainColumn

                anchors.top: parent.top

                width: (columns * cellSize) + units.gridUnit
                height: parent.height

                property int columns: showFilterList ? root.columns - filterListColumn.columns : root.columns
                property Item visibleGrid: mainGrid

                function tryActivate(row, col) {
                    if (visibleGrid) {
                        visibleGrid.tryActivate(row, col);
                    }
                }


                Item {
                    id: mainGridContainer

                    anchors.fill: parent
                    z: (opacity == 1.0) ? 1 : 0

                    enabled: (opacity == 1.0) ? 1 : 0

                    property int headerHeight: mainColumnLabel.height + mainColumnLabelUnderline.height + units.largeSpacing

                    opacity: {
                        if (searching) {
                            return 0.0;
                        }

                        if (filterList.allApps) {
                            return 0.0;
                        }

                        return 1.0;
                    }

                    onOpacityChanged: {
                        if (opacity == 1.0) {
                            mainColumn.visibleGrid = mainGrid;
                        }
                    }

                    PlasmaExtras.Heading {
                        id: mainColumnLabel

                        anchors {
                            top: parent.top
                        }

                        x: units.smallSpacing
                        width: parent.width - x

                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        opacity: 1.0

                        color: "white"

                        level: 1

                        text: funnelModel.description 
                    }

                    PlasmaCore.SvgItem {
                        id: mainColumnLabelUnderline

                        visible: mainGrid.count

                        anchors {
                            top: mainColumnLabel.bottom
                        }

                        width: parent.width - units.gridUnit
                        height: lineSvg.horLineHeight

                        svg: lineSvg
                        elementId: "horizontal-line"
                    }

                    ItemGridView {
                        id: mainGrid

                        anchors {
                            top: mainColumnLabelUnderline.bottom
                            topMargin: units.largeSpacing
                        }

                        width: parent.width
                        height: parent.height

                        cellWidth: cellSize
                        cellHeight: cellWidth
                        iconSize: root.iconSize

                        model: funnelModel

                        onCurrentIndexChanged: {
                            preloadAllAppsTimer.defer();
                        }

                        onKeyNavLeft: {
                                
                        }

                        onKeyNavRight: {
                            if(showFilterList) {
                                filterListScrollArea.focus = true;
                            }
                        }

                        onKeyNavUp: {
                          
                        }

                        onItemActivated: {
                            
                        }
                    }
                }

                ItemMultiGridView {
                    id: allAppsGrid

                    anchors {
                        top: parent.top
                    }

                    z: (opacity == 1.0) ? 1 : 0
                    width: parent.width
                    height: parent.height

                    enabled: (opacity == 1.0) ? 1 : 0

                    opacity: filterList.allApps ? 1.0 : 0.0

                    onOpacityChanged: {
                        if (opacity == 1.0) {
                            allAppsGrid.flickableItem.contentY = 0;
                            mainColumn.visibleGrid = allAppsGrid;
                        }
                    }

                    onKeyNavLeft: {
                       
                    }

                    onKeyNavRight: {
                        if (showFilterList) {
                            filterListScrollArea.focus = true;
                        }
                    }
                }

                ItemMultiGridView {
                    id: runnerGrid

                    anchors {
                        top: parent.top
                    }

                    z: (opacity == 1.0) ? 1 : 0
                    width: parent.width
                    height: parent.height

                    enabled: (opacity == 1.0) ? 1 : 0

                    model: runnerModel

                    grabFocus: true

                    opacity: (searching) ? 1.0 : 0.0

                    onOpacityChanged: {
                        if (opacity == 1.0) {
                            mainColumn.visibleGrid = runnerGrid;
                        }
                    }

                    onKeyNavLeft: {
                    
                    }
                }

                Keys.onPressed: {
                    if (event.key == Qt.Key_Tab) {
                        event.accepted = true;

                        if (filterList.enabled) {
                            filterList.forceActiveFocus();
                        }
                    } else if (event.key == Qt.Key_Backtab) {
                        event.accepted = true;

                        if (searching) {
                            cancelSearchButton.focus = true;
                        }
                    }
                }
            }

            Item {
                id: filterListColumn

                visible: showFilterList

                anchors {
                    top: parent.top
                    topMargin: mainColumnLabelUnderline.y + mainColumnLabelUnderline.height + units.largeSpacing
                    bottom: parent.bottom
                }

                width: columns * cellSize

                property int columns: 3

                PlasmaExtras.ScrollArea {
                    id: filterListScrollArea

                    x: root.visible ? 0 : units.gridUnit

                    Behavior on x { SmoothedAnimation { duration: units.longDuration; velocity: 0.01 } }

                    width: parent.width
                    height: mainGrid.height

                    enabled: showFilterList ? !searching : false

                    property alias currentIndex: filterList.currentIndex

                    opacity: root.visible ? (searching ? 0.30 : 1.0) : 0.3

                    Behavior on opacity { SmoothedAnimation { duration: units.longDuration; velocity: 0.01 } }

                    verticalScrollBarPolicy: (opacity == 1.0) ? Qt.ScrollBarAsNeeded : Qt.ScrollBarAlwaysOff

                    onEnabledChanged: {
                        if (!enabled) {
                            filterList.currentIndex = -1;
                        }
                    }

                    onCurrentIndexChanged: {
                        focus = (currentIndex != -1);
                    }

                    ListView {
                        id: filterList

                        focus: true

                        property bool allApps: false
                        property int eligibleWidth: width
                        property int hItemMargins: Math.max(highlightItemSvg.margins.left + highlightItemSvg.margins.right,
                            listItemSvg.margins.left + listItemSvg.margins.right)

                        model: rootModel

                        boundsBehavior: Flickable.StopAtBounds
                        snapMode: ListView.SnapToItem
                        spacing: 0
                        keyNavigationWraps: true

                        delegate: MouseArea {
                            id: item

                            signal actionTriggered(string actionId, variant actionArgument)
                            signal aboutToShowActionMenu(variant actionMenu)

                            property var m: model
                            property int textWidth: filterListLabel.contentWidth
                            property int mouseCol
                            property bool hasActionList: ((model.favoriteId != null)
                                || (("hasActionList" in model) && (model.hasActionList == true)))
                            property Item menu: actionMenu

                            width: parent.width
                            height: Math.ceil((filterListLabel.paintedHeight
                                + Math.max(highlightItemSvg.margins.top + highlightItemSvg.margins.bottom,
                                listItemSvg.margins.top + listItemSvg.margins.bottom)) / 2) * 2

                            Accessible.role: Accessible.MenuItem
                            Accessible.name: model.display

                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            hoverEnabled: true

                            onContainsMouseChanged: {
                                if (!containsMouse) {
                                    updateCurrentItemTimer.stop();
                                }
                            }

                            onPositionChanged: { // Lazy menu implementation.
                                mouseCol = mouse.x;

                                if (justOpenedTimer.running || ListView.view.currentIndex == 0 || index == ListView.view.currentIndex) {
                                    updateCurrentItem();
                                } else if ((index == ListView.view.currentIndex - 1) && mouse.y < (height - 6)
                                    || (index == ListView.view.currentIndex + 1) && mouse.y > 5) {

                                    if (mouse.x > ListView.view.eligibleWidth - 5) {
                                        updateCurrentItem();
                                    }
                                } else if (mouse.x > ListView.view.eligibleWidth) {
                                    updateCurrentItem();
                                }

                                updateCurrentItemTimer.restart();
                            }

                            onPressed: {
                                if (mouse.buttons & Qt.RightButton) {
                                    if (hasActionList) {
                                        openActionMenu(item, mouse.x, mouse.y);
                                    }
                                }
                            }

                            onClicked: {
                                if (mouse.button == Qt.LeftButton) {
                                    updateCurrentItem();
                                }
                            }

                            onAboutToShowActionMenu: {
                                var actionList = hasActionList ? model.actionList : [];
                                Tools.fillActionMenu(i18n, actionMenu, actionList, ListView.view.model.favoritesModel, model.favoriteId);
                            }

                            onActionTriggered: {
                                if (Tools.triggerAction(ListView.view.model, model.index, actionId, actionArgument) === true) {
                                    plasmoid.expanded = false;
                                }
                            }

                            function openActionMenu(visualParent, x, y) {
                                aboutToShowActionMenu(actionMenu);
                                actionMenu.visualParent = visualParent;
                                actionMenu.open(x, y);
                            }

                            function updateCurrentItem() {
                                ListView.view.currentIndex = index;
                                ListView.view.eligibleWidth = Math.min(width, mouseCol);
                            }

                            ActionMenu {
                                id: actionMenu

                                onActionClicked: {
                                    actionTriggered(actionId, actionArgument);
                                }
                            }

                            Timer {
                                id: updateCurrentItemTimer

                                interval: 50
                                repeat: false

                                onTriggered: parent.updateCurrentItem()
                            }

                            PlasmaExtras.Heading {
                                id: filterListLabel

                                anchors {
                                    fill: parent
                                    leftMargin: highlightItemSvg.margins.left
                                    rightMargin: highlightItemSvg.margins.right
                                }

                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                opacity: 1.0

                                color: "white"

                                level: 5

                                text: model.display
                            }
                        }

                        highlight: PlasmaComponents.Highlight {
                            anchors {
                                top: filterList.currentItem ? filterList.currentItem.top : undefined
                                left: filterList.currentItem ? filterList.currentItem.left : undefined
                                bottom: filterList.currentItem ? filterList.currentItem.bottom : undefined
                            }

                            opacity: filterListScrollArea.focus ? 1.0 : 0.7

                            width: (highlightItemSvg.margins.left
                                + filterList.currentItem.textWidth
                                + highlightItemSvg.margins.right
                                + units.smallSpacing)

                            visible: filterList.currentItem
                        }

                        highlightFollowsCurrentItem: false
                        highlightMoveDuration: 0
                        highlightResizeDuration: 0

                        onCurrentIndexChanged: applyFilter()

                        onCountChanged: {
                            var width = 0;

                            for (var i = 0; i < rootModel.count; ++i) {
                                headingMetrics.text = rootModel.labelForRow(i);

                                if (headingMetrics.width > width) {
                                    width = headingMetrics.width;
                                }
                            }


                            //@todo just adding -1 here since i reduced the header level
                            filterListColumn.columns = Math.ceil(width / cellSize);
                            filterListScrollArea.width = width + hItemMargins + (units.gridUnit * 2);
                        }

                        function applyFilter() {
                            if (!searching && currentIndex >= 0) {
                          

                                if (preloadAllAppsTimer.running) {
                                    preloadAllAppsTimer.stop();
                                }

                                var model = rootModel.modelForRow(currentIndex);

                                if (model.description == "KICKER_ALL_MODEL") {
                                    allAppsGrid.model = model;
                                    allApps = true;
                                    funnelModel.sourceModel = null;
                                    preloadAllAppsTimer.done = true;
                                } else {
                                    funnelModel.sourceModel = model;
                                    allApps = false;
                                }
                            } else {
                                funnelModel.sourceModel = null;
                                allApps = false;
                            }
                        }

                        Keys.onPressed: {
                            if (event.key == Qt.Key_Left) {
                                event.accepted = true;


                                var currentRow = Math.max(0, Math.ceil(currentItem.y / mainGrid.cellHeight) - 1);
                                mainColumn.tryActivate(currentRow, mainColumn.columns - 1);
                            } else if (event.key == Qt.Key_Tab) {
                                event.accepted = true;
                            } else if (event.key == Qt.Key_Backtab) {
                                event.accepted = true;
                                mainColumn.tryActivate(0, 0);
                            }
                        }
                    }
                }
            }
        }

        onPressed: {
            if (mouse.button == Qt.RightButton) {
                contextMenu.open(mouse.x, mouse.y);
            }
        }

        onClicked: {
            if (mouse.button == Qt.LeftButton) {
                root.toggle();
            }
        }
    }
}
