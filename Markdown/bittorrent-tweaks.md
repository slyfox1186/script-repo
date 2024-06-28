# BitTorrent Optimization Tweaks

To optimize BitTorrent for faster connections to trackers and peers, you can modify the following advanced settings:

## Key Parameters to Adjust

1. **bt.connect_speed**
   - **Description**: Controls the number of connection attempts per second. Increasing this value can help BitTorrent connect to peers faster.
   - **Default**: 25
   - **Suggested**: 50 or higher

2. **bt.enable_tracker**
   - **Description**: Ensures that tracker support is enabled.
   - **Suggested**: `true` (if not already set)

3. **peer.lazy_bitfield**
   - **Description**: Setting this to `false` can sometimes help with faster connections to peers.
   - **Default**: `true`
   - **Suggested**: `false`

4. **net.max_halfopen**
   - **Description**: Sets the maximum number of half-open connections. Increasing this can help with faster connections but may also depend on your operating system's limit.
   - **Default**: 500
   - **Suggested**: 500 (or as high as your OS supports)

5. **bt.transp_disposition**
   - **Description**: Controls the transport protocol preferences.
   - **Default**: Varies
   - **Suggested**: `255` (enables all available transport protocols)

6. **peer.disconnect_inactive_interval**
   - **Description**: Determines the interval (in seconds) after which inactive peers are disconnected.
   - **Default**: 300
   - **Suggested**: 120

7. **rss.update_interval**
   - **Description**: Controls how frequently the RSS feed is updated.
   - **Default**: 15 (minutes)
   - **Suggested**: 5 (minutes)

## Steps to Modify These Settings

1. **Open BitTorrent Preferences**:
   - Launch BitTorrent.
   - Go to `Options` > `Preferences` or press `Ctrl + P`.

2. **Navigate to Advanced Settings**:
   - Click on `Advanced` in the left sidebar.

3. **Modify the Parameters**:
   - Use the search bar to find and modify the following parameters:
     - `bt.connect_speed`: Set to `50` or higher.
     - `bt.enable_tracker`: Ensure it is set to `true`.
     - `peer.lazy_bitfield`: Set to `false`.
     - `net.max_halfopen`: Ensure it is set to `500`.
     - `bt.transp_disposition`: Set to `255`.
     - `peer.disconnect_inactive_interval`: Set to `120`.
     - `rss.update_interval`: Set to `5`.

4. **Apply Changes**:
   - Click `Apply` and then `OK` to save the changes.

5. **Restart BitTorrent**:
   - Close and reopen BitTorrent for the changes to take effect.

By adjusting these settings, you should see an improvement in the speed at which BitTorrent connects to trackers and peers.
