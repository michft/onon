# Local Map and Path Recording

This context covers maps whose appearance can be adapted for screen use and reliable paper reproduction.

## Language

**Base Map**:
The geographic reference map upon which recorded paths and symbols are shown.
_Avoid_: Edited map, annotations

**Display Profile**:
A named set of visual distinctions suited to a particular screen or printing condition.
_Avoid_: Theme, colour mode

**Screen Profile**:
A **Display Profile** designed for ordinary colour screens.

**Blue-Light Print Profile**:
A **Display Profile** designed to remain legible on paper viewed under blue-tinted LED light.

**Greyscale Print Profile**:
A **Display Profile** that maps visually distant colours to visually distant grey values.
_Avoid_: Desaturated map, black-and-white filter

**Recommended Visual Scale**:
A curated set of colours, grey values, line weights, patterns, and outlines chosen to preserve meaningful visual separation.
_Avoid_: Automatic conversion, arbitrary palette, colour-only distinction

**Raw Recording**:
The immutable ordered GPS observations, their available accuracy and motion data, and waypoint observations captured by one **Recording Session**.
_Avoid_: Editable trail, cleaned path

**Trail Overlay**:
An editable geographic line derived from a **Raw Recording** and displayed above the **Base Map**.
_Avoid_: Base-map trail, route

**Direction Arrow**:
A user-placed symbol attached beside a **Trail Overlay** that shows the trail's recorded direction.
_Avoid_: Free-standing arrow, compass heading

**Waypoint**:
A point symbol whose centre dot marks its exact coordinate and whose outer circle keeps it visible.
_Avoid_: Approximate area, trail vertex

**Recording Session**:
A user-started period of location capture that produces one **Raw Recording** and continues through phone sleep or locking.
_Avoid_: Foreground-only tracking, map viewing session

**Offline Map Area**:
A bounded portion of the **Base Map** retained on a device for use without the local map server.
_Avoid_: Whole-map cache, screenshot

**Pending Recording**:
A **Raw Recording** retained on its recording device until it can be transferred to the local server.
_Avoid_: Failed upload, temporary path

**Local-First Recording**:
A recording workflow whose essential capture and recovery remain available without an account or server connection.
_Avoid_: Cloud-first sync, account-owned recording

**Device Pairing**:
A local trust step that authorizes one device to transfer and change map data without creating an account.
_Avoid_: User login, public LAN access

**Print Export**:
A PDF map file prepared by the workspace for transfer to and printing from a laptop or desktop.
_Avoid_: In-app printing, browser screenshot

**Print Scale**:
The fixed relationship between distance on a **Print Export** and distance on the ground.
_Avoid_: Fit-to-page zoom, Recommended Visual Scale

**Sydney Service Area**:
The initial map area east of Parramatta, south of Hornsby, north of Sutherland, and extending one nautical mile offshore.
_Avoid_: Greater Sydney, New South Wales

## Relationships

- A **Base Map** can be presented through one of many **Display Profiles**.
- The **Screen Profile**, **Blue-Light Print Profile**, and **Greyscale Print Profile** are distinct **Display Profiles**.
- A **Display Profile** uses a **Recommended Visual Scale**.
- A **Base Map** can show zero or more **Trail Overlays**.
- A **Trail Overlay** is derived from exactly one **Raw Recording**.
- Editing a **Trail Overlay** never changes its **Raw Recording**.
- MVP editing of a **Trail Overlay** is limited to trimming its ends and removing a selected bad section, with undo and redo.
- A **Direction Arrow** belongs to exactly one **Trail Overlay**.
- A **Direction Arrow** derives its orientation from its **Trail Overlay** and may be moved to either side.
- A **Waypoint** may sit on or off a **Trail Overlay**.
- A **Recording Session** may add zero or more **Waypoints** at the device's current location.
- A **Waypoint** may be added or moved during later map editing.
- A **Recording Session** produces exactly one **Raw Recording**.
- A **Recording Session** is active or paused until the user finishes it.
- Finishing a **Recording Session** requires confirmation.
- An unfinished **Recording Session** survives an app interruption and can resume.
- An **Offline Map Area** contains the map resources needed to view its bounds without the local map server.
- A device may retain overview detail for the whole **Sydney Service Area** and field detail for selected **Offline Map Areas**.
- A completed **Recording Session** may produce a **Pending Recording**.
- A **Pending Recording** remains on its recording device until the local server confirms receipt.
- Repeated transfer of one **Pending Recording** creates only one server copy.
- Every **Recording Session** uses **Local-First Recording**.
- A device completes **Device Pairing** before transferring recordings to the local server.
- A **Print Export** presents the **Base Map**, selected overlays, and one **Display Profile**.
- A **Print Export** uses a **Print Scale** of 1:10,000, 1:15,000, or 1:25,000.
- A **Print Export** uses A4 portrait or landscape and shows its exact crop before export.
- The initial **Base Map** covers the **Sydney Service Area**.

## Example dialogue

> **Dev:** “Should greyscale output simply remove colour from the **Base Map**?”
> **Domain expert:** “No. Use the **Greyscale Print Profile** so features remain distinguishable after printing.”

## Flagged ambiguities

- “Changes to maps” means changing map appearance through a **Display Profile**, not changing geographic source data.
- Automatic colour-to-grey conversion is deferred; initial profiles use **Recommended Visual Scales**.
- Phone sleep or locking does not end an active **Recording Session**.
- Phone sleep or locking does not pause an active **Recording Session**.
- “Honsby” is understood as Hornsby.
- MVP has no accounts; identity and multi-user ownership remain deferred.
- MVP provides PDF **Print Exports**; SVG and image exports remain deferred.
- The default **Print Scale** is 1:10,000.
- Freehand redrawing, splitting, and joining **Trail Overlays** remain deferred.
- Automatic snapping of a **Raw Recording** to mapped roads or paths remains deferred.
