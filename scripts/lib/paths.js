/**
 * Shared Path Constants
 * 
 * Common directory paths used throughout the build system.
 */
const path = require('path');

/** Project root directory (monorepo root) */
const PROJECT_ROOT = path.resolve(__dirname, '../..');

/** Build directory for temporary build artifacts */
const BUILD_ROOT = process.env.ROCKETRIDE_BUILD_ROOT || path.join(PROJECT_ROOT, 'build');

/** Distribution directory for final outputs */
const DIST_ROOT = process.env.ROCKETRIDE_DIST_ROOT || path.join(PROJECT_ROOT, 'dist');

/** Overlay repo building this one as a submodule; null for a plain build */
const OVERLAY_ROOT = process.env.ROCKETRIDE_OVERLAY_ROOT || null;

module.exports = {
    PROJECT_ROOT,
    BUILD_ROOT,
    DIST_ROOT,
    OVERLAY_ROOT
};

