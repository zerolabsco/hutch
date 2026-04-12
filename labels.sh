#!/usr/bin/env bash
set -euo pipefail

TRACKER="hutch"
ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT

label_ticket() {
  local ticket_id="$1"
  shift

  for label in "$@"; do
    echo "Applying label '$label' to ticket #$ticket_id"
    if ! hut todo ticket label "$ticket_id" -t "$TRACKER" -l "$label" 2>"$ERR_FILE"; then
      if grep -q "already assigned to this ticket" "$ERR_FILE"; then
        echo "  already present, skipping"
      else
        cat "$ERR_FILE" >&2
        exit 1
      fi
    fi
  done
}

# v2.16.x
label_ticket 14 enhancement ui ux                         # Home: Collapsible Sections
label_ticket 15 enhancement ui                            # Home: See All Navigation
label_ticket 16 enhancement ui ux                         # Home: Repo-Based Grouping

label_ticket 17 enhancement builds                        # Builds: Auto-Refresh Toggle
label_ticket 18 enhancement builds                        # Builds: Per-Repo Filter
label_ticket 19 enhancement builds ux                     # Builds: Retry/Cancel Polish

label_ticket 20 enhancement tickets ui                    # Tickets: Swipe Actions
label_ticket 21 enhancement tickets ui                    # Tickets: Status and Label Visibility

label_ticket 22 bug inbox ui                              # Inbox: Patch Rendering Fixes
label_ticket 23 enhancement inbox ux                      # Inbox: Reply Flow Polish

label_ticket 24 new-feature theming ui                    # Theming: AMOLED Mode
label_ticket 25 new-feature theming ui                    # Theming: High-Density Mode

# v2.17.x
label_ticket 26 new-feature projects                      # Projects: Project List View
label_ticket 27 new-feature projects                      # Projects: Project Detail View
label_ticket 28 enhancement projects ui                   # Projects: Pin to Home

label_ticket 29 enhancement builds                        # Builds: Log Search
label_ticket 30 enhancement builds                        # Builds: Jump to Error
label_ticket 31 enhancement builds                        # Builds: Artifact List

label_ticket 32 enhancement tickets                       # Tickets: Saved Filters
label_ticket 33 enhancement tickets                       # Tickets: Label Filtering

label_ticket 34 enhancement inbox                         # Inbox: Basic Threading
label_ticket 35 enhancement inbox                         # Inbox: Collapse Long Diffs

# v2.18.x
label_ticket 36 new-feature projects                      # Projects: Create Project
label_ticket 37 enhancement projects                      # Projects: Edit Project
label_ticket 38 enhancement projects                      # Projects: Manage Linked Resources

label_ticket 39 new-feature acl repo                      # ACL: View Permissions
label_ticket 40 enhancement acl repo                      # ACL: Add and Remove Users
label_ticket 41 enhancement acl repo                      # ACL: Edit Permissions

label_ticket 42 enhancement repo                          # Repo Settings: Edit Metadata
label_ticket 43 enhancement repo                          # Repo Settings: Set Default Branch
label_ticket 44 enhancement repo                          # Repo Settings: Visibility Changes

label_ticket 45 new-feature tickets                       # Tickets: Label CRUD
label_ticket 46 enhancement tickets                       # Tickets: Bulk Actions

# v2.19.x
label_ticket 47 new-feature search                        # Search: Per-Type Search
label_ticket 48 enhancement search                        # Search: Recent Searches

label_ticket 49 new-feature accounts                      # Accounts: Multi-Account Support
label_ticket 50 enhancement accounts ui                   # Accounts: Account Switcher UI
label_ticket 51 enhancement accounts performance          # Accounts: Isolated Caching

label_ticket 52 enhancement power                         # Power: Open in Browser
label_ticket 53 enhancement power                         # Power: Copy Actions
label_ticket 54 enhancement power                         # Power: Debug View Toggle

# v2.20.x
label_ticket 55 enhancement navigation ux                 # Navigation: Merge Inbox and Tickets Evaluation

label_ticket 56 enhancement performance                   # Performance: Caching Improvements
label_ticket 57 enhancement performance                   # Performance: List Virtualization

label_ticket 58 enhancement repo                          # Consistency: Git and Mercurial Parity

label_ticket 59 bug api                                   # Errors: Normalize GraphQL Handling

echo "Done."
