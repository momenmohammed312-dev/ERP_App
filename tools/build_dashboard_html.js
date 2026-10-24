const fs = require('fs');
const path = require('path');

const logoB64Path = path.join(__dirname, 'logo_b64.txt');
let logoB64 = '';
if (fs.existsSync(logoB64Path)) {
  logoB64 = fs.readFileSync(logoB64Path, 'utf8').trim();
}

console.log('Logo b64 length:', logoB64.length);

const htmlContent = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>مدار ERP — لوحة إدارة التراخيص والموديولات السحابية</title>
  
  <!-- Modern Clean Arabic Typography (IBM Plex Sans Arabic + Readex Pro) -->
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@300;400;500;600;700&family=Readex+Pro:wght@400;500;600;700&display=swap" rel="stylesheet">
  
  <style>
    /* CSS Reset & Base */
    *, *::before, *::after {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    
    :root {
      --primary: #1677FF;
      --primary-hover: #0958D9;
      --primary-subtle: #E6F4FF;
      --primary-border: #BAE0FF;
      --canvas: #F8FAFC;
      --card-bg: #FFFFFF;
      --text-main: #0F172A;
      --text-secondary: #475569;
      --text-muted: #64748B;
      --border-subtle: #E2E8F0;
      --border-light: #F1F5F9;
      --success: #10B981;
      --success-bg: #ECFDF5;
      --success-text: #059669;
      --danger: #EF4444;
      --danger-bg: #FEF2F2;
      --danger-text: #DC2626;
      --warning: #F59E0B;
      --warning-bg: #FFFBEB;
      --warning-text: #D97706;
      --purple: #8B5CF6;
      --purple-bg: #F5F3FF;
      --purple-text: #7C3AED;
    }

    html, body {
      font-family: 'IBM Plex Sans Arabic', 'Readex Pro', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background-color: var(--canvas);
      color: var(--text-main);
      font-size: 13.5px;
      line-height: 1.5;
      min-height: 100vh;
      direction: rtl;
      text-align: right;
      -webkit-font-smoothing: antialiased;
    }

    /* Icon Sizing ONLY for UI icons (NEVER constrain chart SVGs) */
    .app-sidebar svg, .app-header svg, .stat-icon-wrap svg, .filters-bar svg, .toast-box svg, .modal-box svg, td svg {
      width: 18px;
      height: 18px;
      max-width: 18px;
      max-height: 18px;
      display: inline-block;
      vertical-align: middle;
      flex-shrink: 0;
    }
    .icon-xs { width: 14px !important; height: 14px !important; max-width: 14px !important; max-height: 14px !important; }
    .icon-sm { width: 16px !important; height: 16px !important; max-width: 16px !important; max-height: 16px !important; }
    .icon-md { width: 20px !important; height: 20px !important; max-width: 20px !important; max-height: 20px !important; }
    .icon-lg { width: 24px !important; height: 24px !important; max-width: 24px !important; max-height: 24px !important; }

    /* Explicit Chart SVG Classes (Zero constraints) */
    .chart-svg {
      width: 100% !important;
      height: 100% !important;
      max-width: none !important;
      max-height: none !important;
      display: block !important;
      overflow: visible;
    }
    .donut-svg {
      width: 120px !important;
      height: 120px !important;
      max-width: 120px !important;
      max-height: 120px !important;
      display: block !important;
      overflow: visible;
    }

    /* SPLASH SCREEN STYLES */
    #splashScreen {
      position: fixed;
      inset: 0;
      z-index: 99999;
      background: radial-gradient(ellipse at center, #1E293B 0%, #0B1120 100%);
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: #FFFFFF;
      transition: opacity 0.4s cubic-bezier(0.4, 0, 0.2, 1), transform 0.4s cubic-bezier(0.4, 0, 0.2, 1);
    }
    #splashScreen.fade-out {
      opacity: 0;
      transform: scale(1.03);
      pointer-events: none;
    }
    .splash-logo-wrap {
      width: 96px;
      height: 96px;
      border-radius: 22px;
      background: #0F172A;
      border: 2px solid rgba(234, 179, 8, 0.45);
      box-shadow: 0 0 35px rgba(234, 179, 8, 0.25), 0 10px 25px rgba(0, 0, 0, 0.5);
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 20px;
      animation: splashPulse 2s infinite ease-in-out;
      overflow: hidden;
      padding: 6px;
    }
    .splash-logo-img {
      width: 100%;
      height: 100%;
      object-fit: contain;
    }
    @keyframes splashPulse {
      0%, 100% { transform: scale(1); box-shadow: 0 0 30px rgba(234, 179, 8, 0.2); }
      50% { transform: scale(1.04); box-shadow: 0 0 50px rgba(234, 179, 8, 0.45); }
    }
    .splash-title {
      font-size: 26px;
      font-weight: 800;
      letter-spacing: -0.5px;
      margin-bottom: 6px;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .splash-tag {
      font-size: 11px;
      font-weight: 700;
      background: rgba(22, 119, 255, 0.2);
      color: #60A5FA;
      border: 1px solid rgba(96, 165, 250, 0.3);
      padding: 2px 8px;
      border-radius: 6px;
    }
    .splash-subtitle {
      font-size: 13px;
      color: #94A3B8;
      margin-bottom: 24px;
    }
    .splash-progress-track {
      width: 280px;
      height: 4px;
      background: rgba(255, 255, 255, 0.1);
      border-radius: 10px;
      overflow: hidden;
      position: relative;
    }
    .splash-progress-bar {
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg, #1677FF 0%, #F59E0B 100%);
      border-radius: 10px;
      transition: width 1s cubic-bezier(0.4, 0, 0.2, 1);
    }
    .splash-status-text {
      font-size: 11.5px;
      color: #64748B;
      margin-top: 14px;
      font-family: 'Readex Pro', monospace;
    }

    /* APP LAYOUT */
    .app-layout {
      display: flex;
      min-height: 100vh;
    }

    /* SIDEBAR */
    .app-sidebar {
      width: 260px;
      background: var(--card-bg);
      border-left: 1px solid var(--border-subtle);
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      padding: 16px;
      position: fixed;
      top: 0;
      bottom: 0;
      right: 0;
      z-index: 40;
      transition: transform 0.25s ease;
    }
    .app-main {
      flex: 1;
      margin-right: 260px;
      display: flex;
      flex-direction: column;
      min-width: 0;
      background: var(--canvas);
    }

    /* BRAND BOX IN SIDEBAR */
    .brand-box {
      display: flex;
      align-items: center;
      gap: 12px;
      padding-bottom: 16px;
      border-bottom: 1px solid var(--border-light);
      margin-bottom: 18px;
    }
    .brand-logo-frame {
      width: 44px;
      height: 44px;
      border-radius: 12px;
      overflow: hidden;
      background: #0F172A;
      flex-shrink: 0;
      border: 1px solid rgba(234, 179, 8, 0.35);
      box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 3px;
    }
    .brand-logo-frame img {
      width: 100%;
      height: 100%;
      object-fit: contain;
    }
    .brand-info {
      display: flex;
      flex-direction: column;
    }
    .brand-title {
      font-size: 16px;
      font-weight: 800;
      color: var(--text-main);
      display: flex;
      align-items: center;
      gap: 6px;
      line-height: 1.2;
    }
    .brand-badge {
      font-size: 10px;
      font-weight: 700;
      background: var(--primary-subtle);
      color: var(--primary);
      padding: 1px 6px;
      border-radius: 4px;
      border: 1px solid var(--primary-border);
    }
    .brand-sub {
      font-size: 11px;
      color: var(--text-muted);
      margin-top: 3px;
    }

    /* NAVIGATION BUTTONS */
    .nav-list {
      display: flex;
      flex-direction: column;
      gap: 5px;
    }
    .nav-btn {
      display: flex;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      padding: 10px 14px;
      border-radius: 10px;
      border: 1px solid transparent;
      background: transparent;
      color: var(--text-secondary);
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      text-align: right;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .nav-btn:hover {
      background: var(--canvas);
      color: var(--text-main);
    }
    .nav-btn.active {
      background: var(--primary-subtle);
      color: var(--primary);
      border-color: var(--primary-border);
      font-weight: 700;
    }
    .nav-btn.active svg {
      color: var(--primary);
    }
    .nav-btn-content {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .nav-badge {
      font-size: 11px;
      font-weight: 700;
      padding: 1px 7px;
      border-radius: 20px;
      background: var(--border-light);
      color: var(--text-secondary);
      font-family: 'Readex Pro', monospace;
    }
    .nav-btn.active .nav-badge {
      background: var(--primary-border);
      color: var(--primary-hover);
    }

    /* TOP HEADER APP BAR */
    .app-header {
      background: var(--card-bg);
      border-bottom: 1px solid var(--border-subtle);
      padding: 14px 28px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      position: sticky;
      top: 0;
      z-index: 30;
    }
    .header-info h1 {
      font-size: 18px;
      font-weight: 700;
      color: var(--text-main);
      line-height: 1.2;
    }
    .header-info p {
      font-size: 12px;
      color: var(--text-muted);
      margin-top: 3px;
    }
    .header-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .status-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: 20px;
      background: var(--canvas);
      border: 1px solid var(--border-subtle);
      font-size: 12px;
      font-weight: 600;
      color: var(--text-secondary);
      font-family: 'Readex Pro', monospace;
    }
    .dot-pulse {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--success);
      box-shadow: 0 0 0 2px rgba(16, 185, 129, 0.2);
      animation: pulseDot 2s infinite;
    }
    @keyframes pulseDot {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.6; transform: scale(0.9); }
    }

    /* BUTTONS */
    .btn-mantis {
      background: var(--primary);
      color: #FFFFFF;
      border: 1px solid var(--primary);
      padding: 8px 16px;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 8px;
      box-shadow: 0 1px 3px rgba(22, 119, 255, 0.25);
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .btn-mantis:hover {
      background: var(--primary-hover);
      border-color: var(--primary-hover);
      box-shadow: 0 2px 6px rgba(22, 119, 255, 0.35);
    }
    .btn-subtle {
      background: var(--card-bg);
      border: 1px solid var(--border-subtle);
      color: var(--text-secondary);
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .btn-subtle:hover {
      background: var(--canvas);
      color: var(--text-main);
      border-color: #CBD5E1;
    }

    /* MAIN CONTENT WRAPPER */
    .content-area {
      padding: 24px 28px;
      display: flex;
      flex-direction: column;
      gap: 22px;
    }

    /* KPI STAT CARDS */
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
      gap: 18px;
    }
    .stat-card {
      background: var(--card-bg);
      border: 1px solid var(--border-subtle);
      border-radius: 12px;
      padding: 20px 22px;
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
      transition: all 0.2s ease;
    }
    .stat-card:hover {
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
      border-color: #CBD5E1;
      transform: translateY(-1px);
    }
    .stat-label {
      font-size: 12.5px;
      font-weight: 600;
      color: var(--text-muted);
      margin-bottom: 6px;
    }
    .stat-value {
      font-size: 26px;
      font-weight: 800;
      color: var(--text-main);
      font-family: 'Readex Pro', monospace;
      line-height: 1.1;
      margin-bottom: 6px;
    }
    .stat-trend {
      font-size: 11px;
      font-weight: 600;
      color: var(--success-text);
      display: flex;
      align-items: center;
      gap: 4px;
    }
    .stat-icon-wrap {
      width: 44px;
      height: 44px;
      border-radius: 10px;
      background: var(--primary-subtle);
      color: var(--primary);
      display: flex;
      align-items: center;
      justify-content: center;
      border: 1px solid var(--primary-border);
      flex-shrink: 0;
    }

    /* MANTIS WHITE CARDS */
    .mantis-card {
      background: var(--card-bg);
      border: 1px solid var(--border-subtle);
      border-radius: 14px;
      padding: 22px 24px;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
    }
    .card-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 18px;
    }
    .card-title {
      font-size: 15px;
      font-weight: 700;
      color: var(--text-main);
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card-subtitle {
      font-size: 12px;
      color: var(--text-muted);
      margin-top: 2px;
    }

    /* CHARTS GRID */
    .charts-grid-top {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(420px, 1fr));
      gap: 20px;
    }

    /* MANTIS TAB TOGGLES */
    .tab-toggle-pill {
      display: flex;
      background: var(--border-light);
      border-radius: 8px;
      padding: 3px;
      border: 1px solid var(--border-subtle);
    }
    .tab-toggle-btn {
      padding: 4px 14px;
      border-radius: 6px;
      font-size: 11.5px;
      font-weight: 600;
      border: none;
      background: transparent;
      color: var(--text-secondary);
      cursor: pointer;
      font-family: inherit;
      transition: all 0.15s ease;
    }
    .tab-toggle-btn.active {
      background: var(--card-bg);
      color: var(--primary);
      font-weight: 700;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
    }

    /* SVG CHART CANVASES */
    .svg-chart-container {
      width: 100%;
      height: 180px;
      position: relative;
    }

    /* BAR CHART STYLES */
    .bar-chart-bars-wrap {
      height: 180px;
      display: flex;
      align-items: flex-end;
      justify-content: space-between;
      gap: 8px;
      padding: 0 8px;
      border-bottom: 1px solid var(--border-subtle);
      position: relative;
    }
    .bar-col-item {
      flex: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      height: 100%;
      justify-content: flex-end;
      position: relative;
      cursor: pointer;
    }
    .bar-pillar-bg {
      width: 100%;
      max-width: 22px;
      height: 100%;
      background: #F1F5F9;
      border-radius: 6px 6px 0 0;
      display: flex;
      align-items: flex-end;
      overflow: hidden;
      position: relative;
    }
    .bar-pillar-fill {
      width: 100%;
      background: var(--primary);
      border-radius: 6px 6px 0 0;
      transition: height 0.4s cubic-bezier(0.4, 0, 0.2, 1), background-color 0.2s ease;
    }
    .bar-col-item:hover .bar-pillar-fill {
      background: var(--primary-hover);
    }
    .bar-col-label {
      font-size: 10.5px;
      color: var(--text-muted);
      margin-top: 8px;
      font-weight: 600;
      white-space: nowrap;
    }
    .bar-tooltip-popup {
      position: absolute;
      top: -32px;
      background: #0F172A;
      color: #FFFFFF;
      font-size: 10px;
      font-weight: 700;
      padding: 3px 8px;
      border-radius: 4px;
      white-space: nowrap;
      pointer-events: none;
      opacity: 0;
      transform: translateY(4px);
      transition: all 0.15s ease;
      z-index: 20;
      font-family: 'Readex Pro', monospace;
    }
    .bar-col-item:hover .bar-tooltip-popup {
      opacity: 1;
      transform: translateY(0);
    }

    /* LOWER ANALYTICS GRID */
    .analytics-grid-bottom {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 20px;
    }

    /* TABLE DESIGN */
    .table-container {
      background: var(--card-bg);
      border: 1px solid var(--border-subtle);
      border-radius: 14px;
      overflow-x: auto;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
    }
    table {
      width: 100%;
      border-collapse: collapse;
      text-align: right;
    }
    th {
      background: var(--canvas);
      padding: 13px 18px;
      font-size: 12px;
      font-weight: 700;
      color: var(--text-secondary);
      border-bottom: 1px solid var(--border-subtle);
      white-space: nowrap;
    }
    td {
      padding: 14px 18px;
      font-size: 13px;
      color: var(--text-main);
      border-bottom: 1px solid var(--border-light);
      vertical-align: middle;
    }
    tr:last-child td {
      border-bottom: none;
    }
    tr:hover td {
      background: #FAFCFF;
    }

    /* BADGES */
    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      padding: 3px 10px;
      border-radius: 20px;
      font-size: 11px;
      font-weight: 700;
    }
    .badge-active {
      background: var(--success-bg);
      color: var(--success-text);
      border: 1px solid #A7F3D0;
    }
    .badge-suspended {
      background: var(--danger-bg);
      color: var(--danger-text);
      border: 1px solid #FECACA;
    }
    .badge-plan {
      background: var(--border-light);
      color: var(--text-secondary);
      font-size: 11px;
      font-weight: 700;
      padding: 2px 8px;
      border-radius: 6px;
      border: 1px solid var(--border-subtle);
      font-family: 'Readex Pro', monospace;
    }
    .key-box {
      font-family: 'Readex Pro', monospace;
      font-size: 12px;
      font-weight: 600;
      background: var(--canvas);
      padding: 4px 8px;
      border-radius: 6px;
      border: 1px solid var(--border-subtle);
      color: #1E293B;
      letter-spacing: 0.5px;
      display: inline-block;
    }

    /* MODULE TOGGLE PILLS IN TABLE */
    .modules-wrap {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;
      max-width: 380px;
    }
    .mod-pill {
      font-size: 10.5px;
      font-weight: 600;
      padding: 2px 8px;
      border-radius: 6px;
      cursor: pointer;
      border: 1px solid transparent;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .mod-pill.active {
      background: #EFF6FF;
      color: #1D4ED8;
      border-color: #BFDBFE;
    }
    .mod-pill.active:hover {
      background: #DBEAFE;
    }
    .mod-pill.inactive {
      background: var(--canvas);
      color: #94A3B8;
      border-color: var(--border-subtle);
      text-decoration: line-through;
    }
    .mod-pill.inactive:hover {
      background: #F1F5F9;
      color: #475569;
    }

    /* ACTION BUTTONS */
    .btn-action-start {
      background: var(--success-bg);
      color: var(--success-text);
      border: 1px solid #A7F3D0;
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 11.5px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .btn-action-start:hover {
      background: #D1FAE5;
    }
    .btn-action-stop {
      background: var(--danger-bg);
      color: var(--danger-text);
      border: 1px solid #FECACA;
      padding: 4px 10px;
      border-radius: 6px;
      font-size: 11.5px;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.15s ease;
      font-family: inherit;
    }
    .btn-action-stop:hover {
      background: #FEE2E2;
    }

    /* FILTERS BAR */
    .filters-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      flex-wrap: wrap;
    }
    .search-input-wrap {
      position: relative;
      flex: 1;
      min-width: 260px;
    }
    .search-input {
      width: 100%;
      padding: 9px 38px 9px 12px;
      border-radius: 8px;
      border: 1px solid var(--border-subtle);
      background: var(--card-bg);
      font-size: 13px;
      font-family: inherit;
      color: var(--text-main);
      outline: none;
      transition: border-color 0.15s ease;
    }
    .search-input:focus {
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(22, 119, 255, 0.12);
    }
    .search-icon {
      position: absolute;
      top: 50%;
      right: 12px;
      transform: translateY(-50%);
      color: var(--text-muted);
      pointer-events: none;
    }
    .select-input {
      padding: 9px 14px;
      border-radius: 8px;
      border: 1px solid var(--border-subtle);
      background: var(--card-bg);
      font-size: 12.5px;
      font-family: inherit;
      color: var(--text-main);
      outline: none;
      cursor: pointer;
    }
    .select-input:focus {
      border-color: var(--primary);
    }

    /* MODAL */
    .modal-overlay {
      position: fixed;
      inset: 0;
      background: rgba(15, 23, 42, 0.5);
      backdrop-filter: blur(4px);
      z-index: 1000;
      display: none;
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    .modal-overlay.open {
      display: flex;
    }
    .modal-box {
      background: var(--card-bg);
      border-radius: 16px;
      border: 1px solid var(--border-subtle);
      max-width: 540px;
      width: 100%;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.15);
      overflow: hidden;
      animation: modalPop 0.2s cubic-bezier(0.16, 1, 0.3, 1);
    }
    @keyframes modalPop {
      from { transform: scale(0.95); opacity: 0; }
      to { transform: scale(1); opacity: 1; }
    }
    .modal-header {
      padding: 18px 24px;
      border-bottom: 1px solid var(--border-light);
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .modal-header h3 {
      font-size: 16px;
      font-weight: 700;
      color: var(--text-main);
    }
    .modal-close {
      background: transparent;
      border: none;
      font-size: 20px;
      color: var(--text-muted);
      cursor: pointer;
      padding: 4px;
      line-height: 1;
    }
    .modal-close:hover {
      color: var(--text-main);
    }
    .modal-body {
      padding: 20px 24px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }
    .form-group label {
      display: block;
      font-size: 12px;
      font-weight: 700;
      color: var(--text-secondary);
      margin-bottom: 6px;
    }
    .form-control {
      width: 100%;
      padding: 9px 12px;
      border-radius: 8px;
      border: 1px solid var(--border-subtle);
      background: var(--card-bg);
      font-size: 13px;
      font-family: inherit;
      color: var(--text-main);
      outline: none;
    }
    .form-control:focus {
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(22, 119, 255, 0.12);
    }
    .modal-footer {
      padding: 14px 24px;
      background: var(--canvas);
      border-top: 1px solid var(--border-light);
      display: flex;
      align-items: center;
      justify-content: flex-end;
      gap: 10px;
    }

    /* TOAST */
    .toast-box {
      position: fixed;
      bottom: 24px;
      left: 24px;
      background: #0F172A;
      color: #FFFFFF;
      padding: 10px 18px;
      border-radius: 10px;
      font-size: 12.5px;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 10px;
      box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.2);
      transform: translateY(100px);
      opacity: 0;
      transition: all 0.25s cubic-bezier(0.16, 1, 0.3, 1);
      z-index: 2000;
    }
    .toast-box.show {
      transform: translateY(0);
      opacity: 1;
    }

    /* RESPONSIVE */
    .mobile-menu-btn {
      display: none;
      background: transparent;
      border: none;
      color: var(--text-main);
      cursor: pointer;
    }
    @media (max-width: 900px) {
      .app-sidebar {
        transform: translateX(100%);
      }
      .app-sidebar.open {
        transform: translateX(0);
      }
      .app-main {
        margin-right: 0;
      }
      .mobile-menu-btn {
        display: block;
      }
      .charts-grid-top {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>

  <!-- 1. FULLSCREEN ENTERPRISE SPLASH SCREEN -->
  <div id="splashScreen">
    <div class="splash-logo-wrap">
      <img src="${logoB64 || 'madar_logo.png'}" alt="مدار ERP" class="splash-logo-img" onerror="this.src='madar_logo.png'">
    </div>
    <div class="splash-title">
      <span>مِدار ERP</span>
      <span class="splash-tag">v2.4 Enterprise</span>
    </div>
    <div class="splash-subtitle">نظام إدارة التراخيص وتوزيع الموديولات السحابية</div>
    <div class="splash-progress-track">
      <div id="splashProgressBar" class="splash-progress-bar"></div>
    </div>
    <div id="splashStatusText" class="splash-status-text">جاري الاتصال بقاعدة البيانات السحابية...</div>
  </div>

  <div class="app-layout">

    <!-- 2. SIDEBAR WITH OFFICIAL MADAR GOLDEN "م" LOGO -->
    <aside id="sidebar" class="app-sidebar">
      <div>
        <div class="brand-box">
          <div class="brand-logo-frame">
            <img src="${logoB64 || 'madar_logo.png'}" alt="مدار ERP" onerror="this.src='madar_logo.png'">
          </div>
          <div class="brand-info">
            <div class="brand-title">
              <span>مدار ERP</span>
              <span class="brand-badge">Cloud</span>
            </div>
            <div class="brand-sub">إدارة التراخيص والموديولات</div>
          </div>
        </div>

        <nav class="nav-list">
          <button onclick="setTab('overview')" id="btn-nav-overview" class="nav-btn active">
            <span class="nav-btn-content">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="3" y="3" width="7" height="9"></rect>
                <rect x="14" y="3" width="7" height="5"></rect>
                <rect x="14" y="12" width="7" height="9"></rect>
                <rect x="3" y="16" width="7" height="5"></rect>
              </svg>
              <span>الرئيسية والمؤشرات</span>
            </span>
            <span class="nav-badge" style="background:#E6F4FF; color:#1677FF;">Live</span>
          </button>

          <button onclick="setTab('licenses')" id="btn-nav-licenses" class="nav-btn">
            <span class="nav-btn-content">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"></path>
              </svg>
              <span>إدارة التراخيص والعملاء</span>
            </span>
            <span id="badge-total-lic" class="nav-badge">3</span>
          </button>

          <button onclick="setTab('devices')" id="btn-nav-devices" class="nav-btn">
            <span class="nav-btn-content">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path>
              </svg>
              <span>الأجهزة المعتمدة (GUID)</span>
            </span>
            <span id="badge-total-dev" class="nav-badge">4</span>
          </button>

          <button onclick="setTab('modules')" id="btn-nav-modules" class="nav-btn">
            <span class="nav-btn-content">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"></path>
              </svg>
              <span>كتالوج الموديولات (14 ميزة)</span>
            </span>
          </button>

          <button onclick="setTab('audit')" id="btn-nav-audit" class="nav-btn">
            <span class="nav-btn-content">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"></path>
              </svg>
              <span>سجل العمليات والتدقيق</span>
            </span>
          </button>
        </nav>
      </div>

      <!-- SIDEBAR FOOTER -->
      <div style="border-top: 1px solid var(--border-light); padding-top: 14px; display: flex; flex-direction: column; gap: 8px;">
        <button onclick="replaySplash()" class="btn-subtle" style="width: 100%; justify-content: center; font-size: 11px;">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon-xs"><path d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"></path></svg>
          <span>إعادة عرض شاشة البداية (Splash)</span>
        </button>
        <div style="font-size: 10.5px; color: var(--text-muted); text-align: center;">
          مدار ERP • Mantis Enterprise #1677FF
        </div>
      </div>
    </aside>

    <!-- 3. MAIN DASHBOARD AREA -->
    <main class="app-main">

      <!-- HEADER BAR -->
      <header class="app-header">
        <div style="display: flex; align-items: center; gap: 12px;">
          <button class="mobile-menu-btn" onclick="toggleSidebar()">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6h16M4 12h16M4 18h16"></path></svg>
          </button>
          <div class="header-info">
            <h1 id="pageHeadingTitle">لوحة التحكم والمؤشرات الإحصائية</h1>
            <p id="pageHeadingSubtitle">متابعة فورية لنمو التراخيص، توزيع الباقات، وصلاحيات الموديولات</p>
          </div>
        </div>

        <div class="header-actions">
          <div class="status-pill">
            <span class="dot-pulse"></span>
            <span>المحاكي السحابي (Port 8000)</span>
          </div>

          <button onclick="openCreateModal()" class="btn-mantis">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M12 4v16m8-8H4"></path></svg>
            <span>إصدار ترخيص جديد</span>
          </button>
        </div>
      </header>

      <!-- CONTENT BODY -->
      <div class="content-area">

        <!-- 4 TOP STAT KPI CARDS -->
        <div class="stats-grid">
          
          <div class="stat-card">
            <div>
              <div class="stat-label">إجمالي التراخيص المسجلة</div>
              <div id="stat-total" class="stat-value">3</div>
              <div class="stat-trend">↑ 100% منذ الإطلاق</div>
            </div>
            <div class="stat-icon-wrap">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"></path></svg>
            </div>
          </div>

          <div class="stat-card">
            <div>
              <div class="stat-label">التراخيص النشطة</div>
              <div id="stat-active" class="stat-value" style="color: var(--success-text);">2</div>
              <div class="stat-trend">جاهزة للعمل والربط الفوري</div>
            </div>
            <div class="stat-icon-wrap" style="background: var(--success-bg); color: var(--success-text); border-color: #A7F3D0;">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
            </div>
          </div>

          <div class="stat-card">
            <div>
              <div class="stat-label">تراخيص موقوفة / منتهية</div>
              <div id="stat-suspended" class="stat-value" style="color: var(--danger-text);">1</div>
              <div class="stat-trend" style="color: var(--danger-text);">تتطلب تجديد اشتراك</div>
            </div>
            <div class="stat-icon-wrap" style="background: var(--danger-bg); color: var(--danger-text); border-color: #FECACA;">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>
            </div>
          </div>

          <div class="stat-card">
            <div>
              <div class="stat-label">الأجهزة ونقاط البيع (POS)</div>
              <div id="stat-devices" class="stat-value">4</div>
              <div class="stat-trend" style="color: var(--primary);">بصمات عتاد GUID موثقة</div>
            </div>
            <div class="stat-icon-wrap" style="background: #F8FAFC; color: #475569; border-color: var(--border-subtle);">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"></path></svg>
            </div>
          </div>

        </div>

        <!-- ============================================== -->
        <!-- TAB 1: OVERVIEW & COMPLETE MANTIS CHARTS (DEFAULT) -->
        <!-- ============================================== -->
        <div id="tab-overview" style="display: flex; flex-direction: column; gap: 20px;">
          
          <!-- TOP ROW: 2 FULL MANTIS CHARTS -->
          <div class="charts-grid-top">
            
            <!-- 1. MONTHLY OVERVIEW BAR CHART -->
            <div class="mantis-card">
              <div class="card-header">
                <div>
                  <div class="card-title">حركة إصدار وتجديد التراخيص (Monthly Overview)</div>
                  <div class="card-subtitle">معدل التراخيص المصدرة شهرياً مقارنة بالأهداف</div>
                </div>

                <div class="tab-toggle-pill">
                  <button onclick="toggleChartMode('month')" id="btn-chart-month" class="tab-toggle-btn active">شهري</button>
                  <button onclick="toggleChartMode('week')" id="btn-chart-week" class="tab-toggle-btn">أسبوعي</button>
                </div>
              </div>

              <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 14px;">
                <span id="chart-kpi-val" style="font-size: 24px; font-weight: 800; font-family: 'Readex Pro', monospace; color: var(--text-main);">38 ترخيص</span>
                <span style="font-size: 11px; font-weight: 700; color: var(--success-text); background: var(--success-bg); padding: 2px 8px; border-radius: 12px; border: 1px solid #A7F3D0;">↑ +32.5% نمو ملحوظ</span>
              </div>

              <!-- Bar Chart Visual Track -->
              <div class="bar-chart-bars-wrap" id="barChartContainer">
                <!-- Dynamically populated by JS -->
              </div>

              <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 14px; font-size: 11px; color: var(--text-muted);">
                <div style="display: flex; align-items: center; gap: 14px;">
                  <span><span style="display: inline-block; width: 10px; height: 10px; background: var(--primary); border-radius: 2px;"></span> التراخيص المصدرة</span>
                  <span><span style="display: inline-block; width: 10px; height: 10px; background: #F1F5F9; border-radius: 2px;"></span> السعة القصوى</span>
                </div>
                <span>تحديث فوري تلقائي</span>
              </div>
            </div>

            <!-- 2. GROWTH & CONNECTED DEVICES SPLINE AREA CURVE -->
            <div class="mantis-card">
              <div class="card-header">
                <div>
                  <div class="card-title">منحنى نمو الأجهزة والاتصال (Connected Devices)</div>
                  <div class="card-subtitle">تسارع ربط نقاط البيع (POS) عبر الفروع والمستودعات</div>
                </div>
                <span class="badge-plan" style="font-size: 11.5px; background: var(--primary-subtle); color: var(--primary); border-color: var(--primary-border);">52 جهاز متصل</span>
              </div>

              <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 14px;">
                <span style="font-size: 24px; font-weight: 800; font-family: 'Readex Pro', monospace; color: var(--text-main);">99.8%</span>
                <span style="font-size: 11px; font-weight: 700; color: var(--primary); background: var(--primary-subtle); padding: 2px 8px; border-radius: 12px;">معدل استقرار الاتصال السحابي</span>
              </div>

              <!-- Full Scaled SVG Spline Area Curve -->
              <div class="svg-chart-container">
                <svg viewBox="0 0 540 180" class="chart-svg" preserveAspectRatio="none">
                  <defs>
                    <linearGradient id="mantisAreaGradient" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stop-color="#1677FF" stop-opacity="0.32" />
                      <stop offset="100%" stop-color="#1677FF" stop-opacity="0.01" />
                    </linearGradient>
                  </defs>

                  <!-- Horizontal Grid Lines -->
                  <line x1="0" y1="36" x2="540" y2="36" stroke="#F1F5F9" stroke-dasharray="4 4" stroke-width="1.5" />
                  <line x1="0" y1="72" x2="540" y2="72" stroke="#F1F5F9" stroke-dasharray="4 4" stroke-width="1.5" />
                  <line x1="0" y1="108" x2="540" y2="108" stroke="#F1F5F9" stroke-dasharray="4 4" stroke-width="1.5" />
                  <line x1="0" y1="144" x2="540" y2="144" stroke="#F1F5F9" stroke-dasharray="4 4" stroke-width="1.5" />

                  <!-- Area Fill Path -->
                  <path d="M 20 152 C 90 138, 160 115, 230 88 C 310 62, 390 38, 520 20 L 520 180 L 20 180 Z" fill="url(#mantisAreaGradient)" />

                  <!-- Spline Curve Line -->
                  <path d="M 20 152 C 90 138, 160 115, 230 88 C 310 62, 390 38, 520 20" fill="none" stroke="#1677FF" stroke-width="3" stroke-linecap="round" />

                  <!-- Data Nodes -->
                  <circle cx="20" cy="152" r="5" fill="#FFFFFF" stroke="#1677FF" stroke-width="2.5" />
                  <circle cx="120" cy="126" r="5" fill="#FFFFFF" stroke="#1677FF" stroke-width="2.5" />
                  <circle cx="230" cy="88" r="5" fill="#FFFFFF" stroke="#1677FF" stroke-width="2.5" />
                  <circle cx="360" cy="50" r="5" fill="#FFFFFF" stroke="#1677FF" stroke-width="2.5" />
                  
                  <!-- Pulsing Radar on Latest Point -->
                  <circle cx="520" cy="20" r="10" fill="rgba(22, 119, 255, 0.25)" />
                  <circle cx="520" cy="20" r="5" fill="#1677FF" stroke="#FFFFFF" stroke-width="2.5" />
                </svg>
              </div>

              <div style="display: flex; justify-content: space-between; font-size: 11px; color: var(--text-muted); margin-top: 10px; font-family: 'Readex Pro', sans-serif;">
                <span>أسبوع 1 (8 أجهزة)</span>
                <span>أسبوع 2</span>
                <span>أسبوع 4 (22 جهاز)</span>
                <span>أسبوع 6</span>
                <span style="font-weight: 700; color: var(--primary);">أسبوع 8 (52 جهاز)</span>
              </div>
            </div>

          </div>

          <!-- BOTTOM ROW: DONUT PLANS + MODULES PROGRESS + LIVE ACTIVITY -->
          <div class="analytics-grid-bottom">
            
            <!-- 1. PLANS DISTRIBUTION DONUT -->
            <div class="mantis-card">
              <div class="card-title" style="margin-bottom: 14px;">توزيع باقات الاشتراكات (Plans)</div>
              
              <div style="display: flex; align-items: center; justify-content: space-around; gap: 16px; padding: 8px 0;">
                <div style="position: relative; width: 120px; height: 120px; flex-shrink: 0; display: flex; align-items: center; justify-content: center;">
                  <svg width="120" height="120" viewBox="0 0 120 120" class="donut-svg" style="transform: rotate(-90deg);">
                    <circle cx="60" cy="60" r="44" fill="transparent" stroke="#F1F5F9" stroke-width="14" />
                    <!-- Yearly: 50% = 138 of 276 -->
                    <circle cx="60" cy="60" r="44" fill="transparent" stroke="#1677FF" stroke-width="14" stroke-dasharray="138 276" stroke-dashoffset="0" />
                    <!-- Lifetime: 25% = 69 of 276 -->
                    <circle cx="60" cy="60" r="44" fill="transparent" stroke="#10B981" stroke-width="14" stroke-dasharray="69 276" stroke-dashoffset="-138" />
                    <!-- Monthly: 15% = 41 of 276 -->
                    <circle cx="60" cy="60" r="44" fill="transparent" stroke="#F59E0B" stroke-width="14" stroke-dasharray="41 276" stroke-dashoffset="-207" />
                    <!-- Trial: 10% = 28 of 276 -->
                    <circle cx="60" cy="60" r="44" fill="transparent" stroke="#8B5CF6" stroke-width="14" stroke-dasharray="28 276" stroke-dashoffset="-248" />
                  </svg>
                  <div style="position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; pointer-events: none;">
                    <span style="font-size: 19px; font-weight: 800; font-family: 'Readex Pro', monospace; color: var(--text-main); line-height: 1;">38</span>
                    <span style="font-size: 10px; color: var(--text-muted); margin-top: 2px;">ترخيص</span>
                  </div>
                </div>

                <div style="display: flex; flex-direction: column; gap: 9px; flex: 1; font-size: 12px;">
                  <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span style="color: var(--text-secondary); display: flex; align-items: center; gap: 6px;">
                      <span style="width: 8px; height: 8px; border-radius: 50%; background: #1677FF;"></span>
                      سنوي (Yearly)
                    </span>
                    <span style="font-weight: 700; font-family: 'Readex Pro', monospace;">50% (19)</span>
                  </div>
                  <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span style="color: var(--text-secondary); display: flex; align-items: center; gap: 6px;">
                      <span style="width: 8px; height: 8px; border-radius: 50%; background: #10B981;"></span>
                      مدى الحياة (Lifetime)
                    </span>
                    <span style="font-weight: 700; font-family: 'Readex Pro', monospace;">25% (9)</span>
                  </div>
                  <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span style="color: var(--text-secondary); display: flex; align-items: center; gap: 6px;">
                      <span style="width: 8px; height: 8px; border-radius: 50%; background: #F59E0B;"></span>
                      شهري (Monthly)
                    </span>
                    <span style="font-weight: 700; font-family: 'Readex Pro', monospace;">15% (6)</span>
                  </div>
                  <div style="display: flex; justify-content: space-between; align-items: center;">
                    <span style="color: var(--text-secondary); display: flex; align-items: center; gap: 6px;">
                      <span style="width: 8px; height: 8px; border-radius: 50%; background: #8B5CF6;"></span>
                      تجريبي (Trial)
                    </span>
                    <span style="font-weight: 700; font-family: 'Readex Pro', monospace;">10% (4)</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- 2. TOP MODULES ADOPTION PROGRESS -->
            <div class="mantis-card">
              <div class="card-title" style="margin-bottom: 14px;">معدل اعتماد الموديولات الإضافية</div>
              <div style="display: flex; flex-direction: column; gap: 11px;" id="modulesProgressWrap">
                <!-- Populated dynamically -->
              </div>
            </div>

            <!-- 3. LIVE ACTIVITY STREAM -->
            <div class="mantis-card">
              <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px;">
                <div class="card-title">سجل العمليات المباشر (Live Stream)</div>
                <span class="dot-pulse"></span>
              </div>
              <div style="display: flex; flex-direction: column; gap: 10px;" id="activityStreamWrap">
                <!-- Populated dynamically -->
              </div>
            </div>

          </div>

        </div>

        <!-- ============================================== -->
        <!-- TAB 2: LICENSES MANAGEMENT (FULL TABLE & CONTROLS) -->
        <!-- ============================================== -->
        <div id="tab-licenses" style="display: none; flex-direction: column; gap: 16px;">
          
          <div class="mantis-card">
            <div class="filters-bar">
              <div class="search-input-wrap">
                <input type="text" id="searchInput" oninput="filterLicenses()" placeholder="بحث باسم العميل أو مفتاح الترخيص السحابي..." class="search-input">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="search-icon"><path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
              </div>

              <div style="display: flex; gap: 10px; flex-wrap: wrap;">
                <select id="statusFilter" onchange="filterLicenses()" class="select-input">
                  <option value="all">كافة الحالات (الكل)</option>
                  <option value="active">نشط فقط (Active)</option>
                  <option value="suspended">موقوف فقط (Suspended)</option>
                </select>

                <select id="moduleFilter" onchange="filterLicenses()" class="select-input">
                  <option value="all">كافة الموديولات</option>
                  <option value="manufacturing">⚙️ التصنيع وتكاليف الإنتاج</option>
                  <option value="staff_management">👔 إدارة الموظفين والرواتب</option>
                  <option value="custody_management">💼 العهد المالية للمناديب</option>
                  <option value="multi_warehouse">🏬 الفروع وتعدد المخازن</option>
                </select>
              </div>
            </div>
          </div>

          <!-- Full Responsive Licenses Table -->
          <div class="table-container">
            <table>
              <thead>
                <tr>
                  <th>العميل / المؤسسة</th>
                  <th>مفتاح الترخيص السحابي</th>
                  <th>نوع الباقة والصلاحية</th>
                  <th>الحالة</th>
                  <th>الموديولات المصرح بها (انقر للتفعيل/الإلغاء الفوري)</th>
                  <th>الأجهزة</th>
                  <th style="text-align: center;">إجراءات الترخيص</th>
                </tr>
              </thead>
              <tbody id="licensesTableBody">
                <!-- Populated by JS -->
              </tbody>
            </table>
          </div>
        </div>

        <!-- ============================================== -->
        <!-- TAB 3: AUTHORIZED HARDWARE DEVICES (GUID) -->
        <!-- ============================================== -->
        <div id="tab-devices" style="display: none; flex-direction: column; gap: 16px;">
          <div class="mantis-card">
            <div class="card-title">سجل الأجهزة المعتمدة وبصمات العتاد (Hardware GUID)</div>
            <div class="card-subtitle">الربط محمي ببصمة العتاد لكل نقطة بيع. يمكنك فك ارتباط أي جهاز لتمكين العميل من ربط جهاز بديل.</div>
          </div>

          <div class="table-container">
            <table>
              <thead>
                <tr>
                  <th>العميل التابع له</th>
                  <th>بصمة العتاد (Hardware GUID)</th>
                  <th>اسم الجهاز والنظام</th>
                  <th>آخر ظهور سحابي</th>
                  <th style="text-align: center;">إجراء فك الارتباط</th>
                </tr>
              </thead>
              <tbody id="devicesTableBody">
                <!-- Populated by JS -->
              </tbody>
            </table>
          </div>
        </div>

        <!-- ============================================== -->
        <!-- TAB 4: MODULES CATALOG (14 GATED MODULES) -->
        <!-- ============================================== -->
        <div id="tab-modules" style="display: none; flex-direction: column; gap: 16px;">
          <div class="mantis-card">
            <div class="card-title" style="font-size: 16px;">كتالوج موديولات منظومة مدار ERP (14 موديول متوافق)</div>
            <div class="card-subtitle">التطبيق مبني بتقنية Modular Feature Gating عبر التراخيص السحابية، مما يتيح تفعيل وإغلاق أي ميزة بضغطة زر.</div>
          </div>

          <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px;" id="catalogGrid">
            <!-- Populated by JS -->
          </div>
        </div>

        <!-- ============================================== -->
        <!-- TAB 5: AUDIT LOGS & SECURITY TRAIL -->
        <!-- ============================================== -->
        <div id="tab-audit" style="display: none; flex-direction: column; gap: 16px;">
          <div class="mantis-card">
            <div class="card-title" style="margin-bottom: 14px;">سجل التدقيق الأمني والعمليات الإدارية</div>
            <div style="display: flex; flex-direction: column; gap: 12px;" id="auditLogsContainer">
              <!-- Populated by JS -->
            </div>
          </div>
        </div>

      </div>
    </main>
  </div>

  <!-- MODAL: ISSUE NEW LICENSE -->
  <div id="createModal" class="modal-overlay">
    <div class="modal-box">
      <div class="modal-header">
        <h3>إصدار ترخيص سحابي جديد</h3>
        <button onclick="closeCreateModal()" class="modal-close">&times;</button>
      </div>

      <div class="modal-body">
        <div class="form-group">
          <label>اسم العميل / المؤسسة التجارية *</label>
          <input type="text" id="mClientName" placeholder="مثال: شركة الصفا للتوكيلات والتجارة" class="form-control">
        </div>

        <div class="form-group">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 5px;">
            <label style="margin-bottom: 0;">مفتاح الترخيص السحابي *</label>
            <button onclick="generateRandomKey()" style="background:none; border:none; color:var(--primary); font-size:11.5px; font-weight:700; cursor:pointer;">توليد مفتاح عشوائي</button>
          </div>
          <input type="text" id="mKey" class="form-control" style="font-family: 'Readex Pro', monospace; letter-spacing: 0.5px;">
        </div>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 14px;">
          <div class="form-group">
            <label>نوع الباقة</label>
            <select id="mPlan" class="form-control">
              <option value="custom">باقة مخصصة (Custom)</option>
              <option value="standard">باقة أساسية (Standard)</option>
              <option value="professional">باقة متقدمة (Professional)</option>
              <option value="enterprise">باقة شاملة (Enterprise)</option>
            </select>
          </div>
          <div class="form-group">
            <label>الحد الأقصى للأجهزة (POS)</label>
            <input type="number" id="mMaxDevices" value="1" min="1" max="50" class="form-control" style="font-family: 'Readex Pro', monospace;">
          </div>
        </div>

        <div class="form-group">
          <label>الموديولات المصرح بتشغيلها:</label>
          <div style="background:var(--canvas); border:1px solid var(--border-subtle); padding:14px; border-radius:10px; display:flex; flex-direction:column; gap:10px;">
            <div style="font-size:11px; font-weight:700; color:var(--text-muted);">الموديولات المتقدمة القابلة للتفعيل:</div>
            <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px; font-size:12px;">
              <label style="display:flex; align-items:center; gap:6px; cursor:pointer;"><input type="checkbox" id="m_manufacturing"> ⚙️ التصنيع وتكاليف الإنتاج</label>
              <label style="display:flex; align-items:center; gap:6px; cursor:pointer;"><input type="checkbox" id="m_staff"> 👔 إدارة الموظفين والرواتب</label>
              <label style="display:flex; align-items:center; gap:6px; cursor:pointer;"><input type="checkbox" id="m_custody"> 💼 العهد المالية للمناديب</label>
              <label style="display:flex; align-items:center; gap:6px; cursor:pointer;"><input type="checkbox" id="m_expenses" checked> 💸 المصروفات والخزينة</label>
              <label style="display:flex; align-items:center; gap:6px; cursor:pointer;"><input type="checkbox" id="m_multi_warehouse"> 🏬 الفروع والمخازن</label>
              <label style="display:flex; align-items:center; gap:6px; cursor:pointer;"><input type="checkbox" id="m_advanced_reports"> 📈 التقارير المتقدمة والأرباح</label>
            </div>
          </div>
        </div>
      </div>

      <div class="modal-footer">
        <button onclick="closeCreateModal()" class="btn-subtle">إلغاء</button>
        <button onclick="saveNewLicense()" class="btn-mantis">حفظ وإصدار الترخيص</button>
      </div>
    </div>
  </div>

  <!-- TOAST NOTIFICATION -->
  <div id="toast" class="toast-box">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" class="icon-sm" style="color: #10B981;"><path d="M5 13l4 4L19 7"></path></svg>
    <span id="toast-msg">تمت العملية بنجاح</span>
  </div>

  <!-- JAVASCRIPT STATE ENGINE -->
  <script>
    const state = {
      activeTab: 'overview',
      chartMode: 'month',
      licenses: [
        {
          id: 'lic-1',
          client_name: 'شركة النور للمقاولات والتجارة',
          license_key: 'POS-NUR2-8921-X4K9',
          plan_type: 'professional',
          status: 'active',
          max_devices: 2,
          device_count: 2,
          created_at: '2026-09-01T10:00:00Z',
          expires_at: '2027-09-01T10:00:00Z',
          enabled_modules: ['sales', 'inventory', 'customers', 'reports', 'manufacturing', 'expenses', 'staff_management']
        },
        {
          id: 'lic-2',
          client_name: 'مؤسسة الفتح لقطع الغيار',
          license_key: 'POS-FTH7-1049-M9P2',
          plan_type: 'standard',
          status: 'active',
          max_devices: 1,
          device_count: 1,
          created_at: '2026-09-15T12:00:00Z',
          expires_at: '2027-09-15T12:00:00Z',
          enabled_modules: ['sales', 'inventory', 'customers', 'reports', 'expenses']
        },
        {
          id: 'lic-3',
          client_name: 'سلسلة أسواق البركة',
          license_key: 'POS-BRK9-5501-Q8Z1',
          plan_type: 'custom',
          status: 'suspended',
          max_devices: 3,
          device_count: 1,
          created_at: '2026-08-10T08:00:00Z',
          expires_at: '2026-10-01T08:00:00Z',
          enabled_modules: ['sales', 'inventory', 'customers', 'reports', 'custody_management', 'multi_warehouse']
        }
      ],
      devices: [
        { id: 'dev-1', license_id: 'lic-1', client_name: 'شركة النور للمقاولات والتجارة', device_guid: 'WIN-89412-A9F0', device_name: 'Desktop-Cashier-01 (Win 11)', last_seen_at: '2026-10-06T12:45:00Z' },
        { id: 'dev-2', license_id: 'lic-1', client_name: 'شركة النور للمقاولات والتجارة', device_guid: 'WIN-89412-B8E1', device_name: 'Laptop-Admin (Win 10)', last_seen_at: '2026-10-06T11:20:00Z' },
        { id: 'dev-3', license_id: 'lic-2', client_name: 'مؤسسة الفتح لقطع الغيار', device_guid: 'WIN-55102-X9C3', device_name: 'Main-Terminal (Win 11)', last_seen_at: '2026-10-06T13:10:00Z' },
        { id: 'dev-4', license_id: 'lic-3', client_name: 'سلسلة أسواق البركة', device_guid: 'WIN-12093-K3D8', device_name: 'Branch-POS-01 (Win 10)', last_seen_at: '2026-09-30T17:00:00Z' }
      ],
      modulesMeta: {
        'sales': { name: 'المبيعات ونقاط البيع', core: true, desc: 'إصدار فواتير الكاشير والباركود' },
        'inventory': { name: 'المخزون والأصناف', core: true, desc: 'حركات المستودعات والباركود والحد الأدنى' },
        'customers': { name: 'العملاء والديون', core: true, desc: 'سجل العملاء وحسابات الآجل' },
        'reports': { name: 'التقارير اليومية', core: true, desc: 'تقارير المبيعات والوردية النقدية' },
        'manufacturing': { name: 'التصنيع وتكاليف الإنتاج', core: false, desc: 'أوامر التشغيل وتكلفة الخامات ووصفات الإنتاج (BOM)' },
        'staff_management': { name: 'إدارة الموظفين والرواتب', core: false, desc: 'الحضور والغياب والمسيرات والسلف' },
        'custody_management': { name: 'العهد المالية', core: false, desc: 'صرف وتسوية العهد لمندوبي المبيعات' },
        'expenses': { name: 'المصروفات والخزينة', core: false, desc: 'بنود الصرف واليومية وحسابات الصندوق' },
        'multi_warehouse': { name: 'الفروع وتعدد المخازن', core: false, desc: 'التحويلات بين الفروع وجرد المستودعات المتعددة' },
        'advanced_reports': { name: 'التقارير المتقدمة والأرباح', core: false, desc: 'تحليلات هوامش الربحية وقوائم الدخل التراكمية' }
      },
      auditLogs: [
        { time: 'منذ 10 دقائق', event: 'تحديث موديول التصنيع', desc: 'تم تفعيل موديول التصنيع لترخيص شركة النور' },
        { time: 'منذ ساعة', event: 'تسجيل جهاز جديد', desc: 'تم ربط جهاز Main-Terminal بنجاح عبر GUID' },
        { time: 'منذ يوم', event: 'إيقاف مؤقت للترخيص', desc: 'تم إيقاف ترخيص أسواق البركة لانتهاء مدة الاشتراك' }
      ]
    };

    // TAB NAVIGATION
    function setTab(tab) {
      state.activeTab = tab;
      const tabs = ['overview', 'licenses', 'devices', 'modules', 'audit'];
      
      const titles = {
        'overview': { title: 'لوحة التحكم والمؤشرات الإحصائية', sub: 'متابعة فورية لنمو التراخيص، توزيع الباقات، وصلاحيات الموديولات' },
        'licenses': { title: 'إدارة التراخيص والعملاء', sub: 'تحكم فوري ومباشر في صلاحيات النسخ وأجهزة نقاط البيع لكل عميل' },
        'devices': { title: 'الأجهزة المعتمدة وبصمات العتاد', sub: 'إدارة الأجهزة الموثقة عبر Hardware GUID وإمكانية فك الارتباط' },
        'modules': { title: 'كتالوج الموديولات السحابية', sub: 'استعراض 14 ميزة وموديول متاحين للتحكم عبر التراخيص السحابية' },
        'audit': { title: 'سجل العمليات والتدقيق', sub: 'تتبع شامل لجميع التغييرات الإدارية والأمنية في النظام' }
      };

      tabs.forEach(t => {
        const wrap = document.getElementById('tab-' + t);
        const btn = document.getElementById('btn-nav-' + t);
        if (t === tab) {
          if (wrap) wrap.style.display = 'flex';
          if (btn) btn.className = 'nav-btn active';
        } else {
          if (wrap) wrap.style.display = 'none';
          if (btn) btn.className = 'nav-btn';
        }
      });

      if (titles[tab]) {
        document.getElementById('pageHeadingTitle').innerText = titles[tab].title;
        document.getElementById('pageHeadingSubtitle').innerText = titles[tab].sub;
      }

      if (tab === 'overview') renderMantisCharts();
    }

    function toggleSidebar() {
      document.getElementById('sidebar').classList.toggle('open');
    }

    // SPLASH SCREEN CONTROLLER
    function runSplash() {
      const splash = document.getElementById('splashScreen');
      if (!splash) return;
      const bar = document.getElementById('splashProgressBar');
      const txt = document.getElementById('splashStatusText');
      
      splash.classList.remove('fade-out');
      splash.style.display = 'flex';
      bar.style.width = '0%';
      txt.innerText = 'جاري الاتصال بقاعدة البيانات السحابية...';

      setTimeout(() => {
        bar.style.width = '45%';
        txt.innerText = 'التحقق من التراخيص السحابية وبصمات العتاد...';
      }, 250);

      setTimeout(() => {
        bar.style.width = '85%';
        txt.innerText = 'تهيئة موديولات مدار ERP ومؤشرات الأداء...';
      }, 550);

      setTimeout(() => {
        bar.style.width = '100%';
        txt.innerText = 'جاهز! جاري فتح لوحة التحكم...';
      }, 850);

      setTimeout(() => {
        splash.classList.add('fade-out');
        setTimeout(() => {
          splash.style.display = 'none';
        }, 450);
      }, 1150);
    }

    function replaySplash() {
      runSplash();
    }

    // CHART TOGGLE
    function toggleChartMode(mode) {
      state.chartMode = mode;
      document.getElementById('btn-chart-month').className = mode === 'month' ? 'tab-toggle-btn active' : 'tab-toggle-btn';
      document.getElementById('btn-chart-week').className = mode === 'week' ? 'tab-toggle-btn active' : 'tab-toggle-btn';
      document.getElementById('chart-kpi-val').innerText = mode === 'month' ? '38 ترخيص' : '59 عملية';
      renderMantisCharts();
    }

    // RENDER MANTIS CHARTS
    function renderMantisCharts() {
      const container = document.getElementById('barChartContainer');
      if (!container) return;
      container.innerHTML = '';

      const monthData = [
        { label: 'يناير', count: 6 }, { label: 'فبراير', count: 10 }, { label: 'مارس', count: 14 },
        { label: 'أبريل', count: 11 }, { label: 'مايو', count: 18 }, { label: 'يونيو', count: 22 },
        { label: 'يوليو', count: 26 }, { label: 'أغسطس', count: 30 }, { label: 'سبتمبر', count: 34 },
        { label: 'أكتوبر', count: 38 }, { label: 'نوفمبر', count: 36 }, { label: 'ديسمبر', count: 40 }
      ];

      const weekData = [
        { label: 'السبت', count: 8 }, { label: 'الأحد', count: 14 }, { label: 'الإثنين', count: 11 },
        { label: 'الثلاثاء', count: 19 }, { label: 'الأربعاء', count: 13 }, { label: 'الخميس', count: 21 },
        { label: 'الجمعة', count: 7 }
      ];

      const data = state.chartMode === 'month' ? monthData : weekData;
      const maxVal = Math.max(...data.map(d => d.count), 1);

      data.forEach(item => {
        const fillHeightPct = Math.round((item.count / maxVal) * 92);
        const col = document.createElement('div');
        col.className = 'bar-col-item';
        col.innerHTML = \`
          <div class="bar-tooltip-popup">\${item.count} ترخيص</div>
          <div class="bar-pillar-bg">
            <div class="bar-pillar-fill" style="height: \${fillHeightPct}%;"></div>
          </div>
          <span class="bar-col-label">\${item.label}</span>
        \`;
        container.appendChild(col);
      });

      // Modules Progress
      const mpw = document.getElementById('modulesProgressWrap');
      if (mpw) {
        mpw.innerHTML = [
          { name: 'إدارة الموظفين والرواتب', pct: 80, count: '18 عميل' },
          { name: 'التقارير المتقدمة والأرباح', pct: 72, count: '16 عميل' },
          { name: 'التصنيع وتكاليف الإنتاج', pct: 65, count: '14 عميل' },
          { name: 'العهد المالية والمندوبين', pct: 50, count: '11 عميل' },
          { name: 'الفروع وتعدد المخازن', pct: 40, count: '9 عملاء' }
        ].map(m => \`
          <div>
            <div style="display:flex; justify-content:space-between; font-size:11.5px; margin-bottom:4px;">
              <span style="font-weight:600; color:var(--text-main);">\${m.name}</span>
              <span style="font-family:'Readex Pro', monospace; color:var(--text-muted);">\${m.pct}% (\${m.count})</span>
            </div>
            <div style="width:100%; height:6px; background:#F1F5F9; border-radius:10px; overflow:hidden;">
              <div style="width:\${m.pct}%; height:100%; background:var(--primary); border-radius:10px; transition: width 0.5s ease;"></div>
            </div>
          </div>
        \`).join('');
      }

      // Live Activity Stream
      const asw = document.getElementById('activityStreamWrap');
      if (asw) {
        asw.innerHTML = [
          { title: 'إصدار ترخيص تجاري سنوي', client: 'شركة النور للمقاولات', time: 'منذ 10 دقائق', badge: 'ترخيص جديد', bg: '#EFF6FF', col: '#1D4ED8' },
          { title: 'تفعيل موديول التصنيع ⚙️', client: 'مصنع الأمل للحلويات', time: 'منذ 35 دقيقة', badge: 'موديول', bg: '#ECFDF5', col: '#065F46' },
          { title: 'ربط نقطة بيع POS جديدة', client: 'مؤسسة الفتح لقطع الغيار', time: 'منذ ساعتين', badge: 'جهاز', bg: '#F3E8FF', col: '#6B21A8' }
        ].map(a => \`
          <div style="display:flex; justify-content:space-between; align-items:center; padding:8px 10px; border-radius:8px; background:var(--canvas); font-size:12px; border:1px solid var(--border-light);">
            <div>
              <div style="font-weight:700; color:var(--text-main); font-size:11.5px;">\${a.title}</div>
              <div style="font-size:10.5px; color:var(--text-muted); margin-top:1px;">\${a.client}</div>
            </div>
            <div style="text-align:left;">
              <span style="font-size:9.5px; font-weight:700; padding:2px 7px; border-radius:4px; background:\${a.bg}; color:\${a.col};">\${a.badge}</span>
              <div style="font-size:9.5px; color:#94A3B8; margin-top:3px; font-family:'Readex Pro', sans-serif;">\${a.time}</div>
            </div>
          </div>
        \`).join('');
      }
    }

    // RENDER LICENSES TABLE
    function renderLicenses(items) {
      const tbody = document.getElementById('licensesTableBody');
      tbody.innerHTML = '';
      const list = items || state.licenses;

      if (list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" style="text-align:center; padding:35px; color:#94A3B8;">لا توجد تراخيص مطابقة لمعايير البحث</td></tr>';
        return;
      }

      list.forEach(lic => {
        const tr = document.createElement('tr');
        const optionalKeys = ['manufacturing', 'staff_management', 'custody_management', 'expenses', 'multi_warehouse', 'advanced_reports'];
        const modulesHtml = optionalKeys.map(mKey => {
          const isEnabled = (lic.enabled_modules || []).includes(mKey);
          const meta = state.modulesMeta[mKey] || { name: mKey };
          return \`
            <button onclick="toggleModule('\${lic.id}', '\${mKey}')" class="mod-pill \${isEnabled ? 'active' : 'inactive'}" title="\${isEnabled ? 'انقر للتعطيل' : 'انقر للتفعيل'}">
              \${meta.name}
            </button>
          \`;
        }).join('');

        const statusPill = lic.status === 'active'
          ? \`<span class="badge-status badge-active"><span style="width:6px; height:6px; border-radius:50%; background:#10B981;"></span>نشط</span>\`
          : \`<span class="badge-status badge-suspended"><span style="width:6px; height:6px; border-radius:50%; background:#EF4444;"></span>موقوف</span>\`;

        tr.innerHTML = \`
          <td>
            <div style="font-weight:700; color:var(--text-main);">\${lic.client_name}</div>
            <div style="font-size:11px; color:var(--text-muted); font-family:'Readex Pro', monospace;">\${lic.id}</div>
          </td>
          <td>
            <div style="display:flex; align-items:center; gap:6px;">
              <span class="key-box">\${lic.license_key}</span>
              <button onclick="copyToClipboard('\${lic.license_key}')" title="نسخ المفتاح" style="background:none; border:none; cursor:pointer; color:var(--text-muted);">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="icon-xs"><path d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"></path></svg>
              </button>
            </div>
          </td>
          <td>
            <span class="badge-plan">\${lic.plan_type}</span>
            <div style="font-size:11px; color:var(--text-muted); margin-top:3px; font-family:'Readex Pro', monospace;">حتى \${lic.expires_at.split('T')[0]}</div>
          </td>
          <td>\${statusPill}</td>
          <td><div class="modules-wrap">\${modulesHtml}</div></td>
          <td><span style="font-weight:700; font-family:'Readex Pro', monospace;">\${lic.device_count}</span> <span style="color:var(--text-muted); font-family:'Readex Pro', monospace;">/ \${lic.max_devices}</span></td>
          <td style="text-align:center;">
            <button onclick="toggleLicenseStatus('\${lic.id}')" class="\${lic.status === 'active' ? 'btn-action-stop' : 'btn-action-start'}">
              \${lic.status === 'active' ? 'إيقاف الترخيص' : 'تفعيل الترخيص'}
            </button>
          </td>
        \`;
        tbody.appendChild(tr);
      });
    }

    function toggleModule(licId, moduleName) {
      const lic = state.licenses.find(l => l.id === licId);
      if (!lic) return;
      const idx = lic.enabled_modules.indexOf(moduleName);
      if (idx !== -1) {
        lic.enabled_modules.splice(idx, 1);
        showToast(\`تم إيقاف موديول (\${state.modulesMeta[moduleName]?.name || moduleName}) عن \${lic.client_name}\`);
      } else {
        lic.enabled_modules.push(moduleName);
        showToast(\`تم تفعيل موديول (\${state.modulesMeta[moduleName]?.name || moduleName}) لـ \${lic.client_name}\`);
      }
      renderLicenses();
      updateStats();
      renderMantisCharts();
    }

    function toggleLicenseStatus(licId) {
      const lic = state.licenses.find(l => l.id === licId);
      if (!lic) return;
      lic.status = lic.status === 'active' ? 'suspended' : 'active';
      showToast(\`تم تحديث حالة ترخيص \${lic.client_name} إلى \${lic.status === 'active' ? 'نشط' : 'موقوف'}\`);
      renderLicenses();
      updateStats();
    }

    function filterLicenses() {
      const q = document.getElementById('searchInput').value.toLowerCase().trim();
      const statusF = document.getElementById('statusFilter').value;
      const modF = document.getElementById('moduleFilter').value;

      const filtered = state.licenses.filter(l => {
        const matchQ = l.client_name.toLowerCase().includes(q) || l.license_key.toLowerCase().includes(q);
        const matchStatus = statusF === 'all' || l.status === statusF;
        const matchMod = modF === 'all' || (l.enabled_modules || []).includes(modF);
        return matchQ && matchStatus && matchMod;
      });

      renderLicenses(filtered);
    }

    // DEVICES
    function renderDevices() {
      const tbody = document.getElementById('devicesTableBody');
      tbody.innerHTML = '';
      if (state.devices.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding:35px; color:#94A3B8;">لا توجد أجهزة متصلة بعد</td></tr>';
        return;
      }
      state.devices.forEach(dev => {
        const tr = document.createElement('tr');
        tr.innerHTML = \`
          <td><span style="font-weight:700;">\${dev.client_name}</span></td>
          <td><span class="key-box">\${dev.device_guid}</span></td>
          <td><span style="font-weight:600;">\${dev.device_name}</span></td>
          <td><span style="color:var(--text-muted); font-family:'Readex Pro', monospace;">\${new Date(dev.last_seen_at).toLocaleTimeString('ar-EG')}</span></td>
          <td style="text-align:center;">
            <button onclick="unbindDevice('\${dev.id}')" class="btn-action-stop">فك الارتباط</button>
          </td>
        \`;
        tbody.appendChild(tr);
      });
    }

    function unbindDevice(id) {
      if (confirm('هل أنت متأكد من فك ارتباط هذا الجهاز؟ سيتمكن العميل من ربط جهاز جديد فوراً.')) {
        state.devices = state.devices.filter(d => d.id !== id);
        showToast('تم فك ارتباط الجهاز بنجاح');
        renderDevices();
        updateStats();
      }
    }

    // MODULES CATALOG
    function renderModulesCatalog() {
      const grid = document.getElementById('catalogGrid');
      grid.innerHTML = '';
      Object.keys(state.modulesMeta).forEach(key => {
        const mod = state.modulesMeta[key];
        const card = document.createElement('div');
        card.className = 'mantis-card';
        card.innerHTML = \`
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
            <span style="font-weight:700; font-size:14px; color:var(--text-main);">\${mod.name}</span>
            <span class="\${mod.core ? 'badge-plan' : 'badge-status badge-active'}" style="font-size:10px;">\${mod.core ? 'أساسي' : 'إضافي'}</span>
          </div>
          <p style="font-size:12px; color:var(--text-muted); margin-bottom:12px; line-height:1.5;">\${mod.desc || 'الوظائف الأساسية للنظام'}</p>
          <div style="font-size:11px; color:#94A3B8; font-family:'Readex Pro', monospace; border-top:1px solid var(--border-light); padding-top:8px;">
            معرف الميزة: \${key}
          </div>
        \`;
        grid.appendChild(card);
      });
    }

    // AUDIT LOGS
    function renderAuditLogs() {
      const alc = document.getElementById('auditLogsContainer');
      alc.innerHTML = state.auditLogs.map(log => \`
        <div style="display:flex; align-items:flex-start; gap:12px; padding:12px 14px; border-radius:10px; border:1px solid var(--border-light); background:var(--canvas);">
          <span style="width:8px; height:8px; border-radius:50%; background:var(--primary); margin-top:6px; flex-shrink:0;"></span>
          <div style="flex:1;">
            <div style="display:flex; justify-content:space-between; font-size:12.5px; font-weight:700;">
              <span>\${log.event}</span>
              <span style="font-size:10.5px; color:#94A3B8; font-family:'Readex Pro', sans-serif;">\${log.time}</span>
            </div>
            <div style="font-size:11.5px; color:var(--text-muted); margin-top:2px;">\${log.desc}</div>
          </div>
        </div>
      \`).join('');
    }

    // STATS UPDATE
    function updateStats() {
      const total = state.licenses.length;
      const active = state.licenses.filter(l => l.status === 'active').length;
      const suspended = total - active;
      const devCount = state.devices.length;

      document.getElementById('stat-total').innerText = total;
      document.getElementById('stat-active').innerText = active;
      document.getElementById('stat-suspended').innerText = suspended;
      document.getElementById('stat-devices').innerText = devCount;

      const bLic = document.getElementById('badge-total-lic');
      if (bLic) bLic.innerText = total;
      const bDev = document.getElementById('badge-total-dev');
      if (bDev) bDev.innerText = devCount;
    }

    // MODAL ACTIONS
    function generateRandomKey() {
      const seg = () => Math.random().toString(36).substring(2, 6).toUpperCase();
      document.getElementById('mKey').value = \`POS-\${seg()}-\${seg()}-\${seg()}\`;
    }

    function openCreateModal() {
      document.getElementById('mClientName').value = '';
      generateRandomKey();
      document.getElementById('createModal').classList.add('open');
    }

    function closeCreateModal() {
      document.getElementById('createModal').classList.remove('open');
    }

    function saveNewLicense() {
      const name = document.getElementById('mClientName').value.trim();
      const key = document.getElementById('mKey').value.trim();
      const plan = document.getElementById('mPlan').value;
      const maxDev = parseInt(document.getElementById('mMaxDevices').value) || 1;

      if (!name || !key) {
        alert('يرجى كتابة اسم العميل ومفتاح الترخيص');
        return;
      }

      const enabled = ['sales', 'inventory', 'customers', 'reports'];
      if (document.getElementById('m_manufacturing').checked) enabled.push('manufacturing');
      if (document.getElementById('m_staff').checked) enabled.push('staff_management');
      if (document.getElementById('m_custody').checked) enabled.push('custody_management');
      if (document.getElementById('m_expenses').checked) enabled.push('expenses');
      if (document.getElementById('m_multi_warehouse').checked) enabled.push('multi_warehouse');
      if (document.getElementById('m_advanced_reports').checked) enabled.push('advanced_reports');

      const newLic = {
        id: 'lic-' + (state.licenses.length + 1),
        client_name: name,
        license_key: key,
        plan_type: plan,
        status: 'active',
        max_devices: maxDev,
        device_count: 0,
        created_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 365*24*3600*1000).toISOString(),
        enabled_modules: enabled
      };

      state.licenses.unshift(newLic);
      closeCreateModal();
      showToast(\`تم إصدار ترخيص تجاري جديد لـ \${name}\`);
      renderLicenses();
      updateStats();
      renderMantisCharts();
    }

    function copyToClipboard(text) {
      navigator.clipboard.writeText(text);
      showToast('تم نسخ مفتاح الترخيص للحافظة بنجاح');
    }

    function showToast(msg) {
      const t = document.getElementById('toast');
      const tm = document.getElementById('toast-msg');
      tm.innerText = msg;
      t.classList.add('show');
      setTimeout(() => {
        t.classList.remove('show');
      }, 3000);
    }

    // INITIALIZATION
    window.addEventListener('DOMContentLoaded', () => {
      runSplash();
      renderLicenses();
      renderDevices();
      renderModulesCatalog();
      renderMantisCharts();
      renderAuditLogs();
      updateStats();
    });
  </script>
</body>
</html>
`;

// Write to dist/index.html
const distPath = path.join(__dirname, '..', 'admin_dashboard', 'dist', 'index.html');
fs.writeFileSync(distPath, htmlContent, 'utf8');
console.log('Successfully wrote to:', distPath);

// Write to brain/dashboard_preview.html
const brainPreviewPath = 'C:\\\\Users\\\\Momen\\\\.gemini\\\\antigravity\\\\brain\\\\f994694e-2513-4db3-9515-fed8479f6918\\\\dashboard_preview.html';
fs.writeFileSync(brainPreviewPath, htmlContent, 'utf8');
console.log('Successfully wrote to:', brainPreviewPath);

// Write to admin_dashboard/public/index.html
const publicPath = path.join(__dirname, '..', 'admin_dashboard', 'public', 'index.html');
fs.writeFileSync(publicPath, htmlContent, 'utf8');
console.log('Successfully wrote to:', publicPath);
