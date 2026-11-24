<?php
// DELIBERATELY BROKEN UPDATE FOR IT 123 OPTION 1B LIVE DEMO
// Applying this update causes a syntax/runtime failure (HTTP 500) so
// linkod-update.sh detects the broken update and prints the restore command.

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    throw new \RuntimeException('SIMULATED BROKEN UPDATE: Fatal route configuration error in v1.1-broken');
});
