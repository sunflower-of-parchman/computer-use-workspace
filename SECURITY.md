# Security Policy

## Supported version

Security review currently covers the latest `0.1.0` release and the source on the default branch.

## Report a vulnerability

Report suspected vulnerabilities privately through GitHub Security Advisories for this repository. Include the affected revision, macOS version, command or workflow, security impact, reproduction steps, and the smallest useful diagnostic output.

Do not open a public issue for an unpatched vulnerability. Remove unrelated application data and personal information from screenshots or logs before attaching them.

## Security boundaries

Computer Use Workspace is a local macOS helper. It reads display geometry, application bundle identifiers, process identifiers, window identifiers, and window bounds. It uses macOS Accessibility only for bounded placement, focus restoration, exact-window closure, and graceful termination of an application process recorded as task-owned.

The helper does not read window titles, screen pixels, application content, keystrokes, credentials, or network traffic. It makes no network requests. Lifecycle state is local, temporary, owner-readable only, and insufficient to authorize later window actions without the caller-held receipt returned by placement.

Security reports should focus especially on:

- moving, closing, or terminating a resource that was not created by the task;
- bypassing the pre-existing-window or application ownership checks;
- tampering with lifecycle state or window identity;
- unsafe filesystem handling in local build or runtime state;
- unbounded Accessibility actions; and
- exposure of application, display, or user data beyond the documented fields.
