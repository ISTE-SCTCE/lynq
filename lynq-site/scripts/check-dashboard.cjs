// Run against the local Vite server with playwright-cli run-code --filename.
// Network fixtures are browser-only. No real account or database writes are used.
async (page) => {
  await page.unrouteAll({ behavior: 'ignoreErrors' });
  let failEvents = false;
  await page.route('**/src/core/auth-provider.tsx*', route => route.fulfill({
    contentType: 'application/javascript',
    body: `import { PermissionEngine } from '/src/core/permission-engine.ts';
      const user = { id: 'test-user', name: 'Test Member', role: 'chairman' };
      const permissions = new PermissionEngine(user);
      export const AuthProvider = ({children}) => children;
      export const useAuth = () => ({ currentUser:user, permissions, isAuthenticated:true, isLoading:false, isShowingSplash:false });`,
  }));
  await page.route('https://*.supabase.co/**', async route => {
    const url = { pathname: route.request().url().split('?')[0] };
    if (failEvents && url.pathname.includes('/events')) {
      await route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ message: 'Test outage' }) });
      return;
    }
    let rows = [];
    if (url.pathname.endsWith('/events')) rows = [{ id: 'event-1', title: 'Community design workshop', date: '2026-12-01' }];
    if (url.pathname.endsWith('/tasks')) rows = [{ id: 'task-1', title: 'Prepare the workshop brief', deadline: '2026-12-01' }];
    if (url.pathname.endsWith('/folders')) rows = [{ id: 1, name: 'Creative team' }];
    await route.fulfill({ contentType: 'application/json', headers: { 'content-range': '0-0/1', 'access-control-expose-headers': 'content-range' }, body: JSON.stringify(rows) });
  });
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto('http://127.0.0.1:5173/home');
  await page.getByText('Community design workshop', { exact: true }).waitFor();
  await page.screenshot({ path: 'output/playwright/dashboard-desktop.png', fullPage: true });
  for (const width of [390, 320]) {
    await page.setViewportSize({ width, height: 844 });
    await page.waitForFunction(() => document.querySelector('.liquid-glass-nav-bar').getBoundingClientRect().height < 80);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    if (overflow) throw new Error('Horizontal overflow at ' + width);
  }
  await page.screenshot({ path: 'output/playwright/dashboard-mobile.png', fullPage: true });
  failEvents = true;
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await page.getByRole('alert').waitFor();
  if (!(await page.getByRole('alert').textContent()).includes('Upcoming events')) throw new Error('Missing error feedback');
  failEvents = false;
  await page.getByRole('button', { name: 'Refresh', exact: true }).click();
  await page.getByText('Community design workshop', { exact: true }).waitFor();
  if (await page.getByRole('alert').count()) throw new Error('Error did not clear');
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'dark'));
  await page.screenshot({ path: 'output/playwright/dashboard-dark.png', fullPage: true });
  console.log('PASS: desktop, 390px/320px overflow, error state, retry recovery, dark mode capture.');
}
