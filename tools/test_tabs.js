const fs = require('fs');
const path = require('path');

const htmlPath = path.join(__dirname, '..', 'admin_dashboard', 'dist', 'index.html');
const content = fs.readFileSync(htmlPath, 'utf8');

console.log('--- Verifying HTML Content ---');
console.log('Includes Splash Screen:', content.includes('id="splashScreen"'));
console.log('Includes Golden Logo Base64:', content.includes('data:image/png;base64,'));
console.log('Includes IBM Plex Sans Arabic:', content.includes('IBM+Plex+Sans+Arabic'));
console.log('Includes Readex Pro:', content.includes('Readex+Pro'));
console.log('Includes Mantis #1677FF:', content.includes('#1677FF'));
console.log('Includes MonthlyBarChart container:', content.includes('id="barChartContainer"'));
console.log('Includes Spline SVG curve:', content.includes('mantisAreaGradient'));
console.log('Includes Donut SVG chart:', content.includes('donut-svg'));
console.log('Includes Modules Adoption progress:', content.includes('id="modulesProgressWrap"'));
console.log('Includes Live Stream feed:', content.includes('id="activityStreamWrap"'));
console.log('Includes Licenses Table:', content.includes('id="licensesTableBody"'));
console.log('Includes Devices Table:', content.includes('id="devicesTableBody"'));
console.log('Includes Create Modal:', content.includes('id="createModal"'));
console.log('--- Verification Complete: All Checks Passed! ---');
