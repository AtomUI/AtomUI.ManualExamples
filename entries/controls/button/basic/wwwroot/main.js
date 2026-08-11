import { dotnet } from './_framework/dotnet.js';

const status = document.querySelector('.splash-status');
const splash = status?.closest('.splash');

try {
    const runtime = await dotnet
        .withApplicationArgumentsFromQuery()
        .create();
    splash?.classList.add('splash-close');
    const config = runtime.getConfig();
    await runtime.runMain(config.mainAssemblyName, [globalThis.location.href]);
} catch (error) {
    console.error('[Button_Basic] startup failed', error);
    splash?.classList.remove('splash-close');
    if (status) {
        status.textContent = 'Unable to load preview.';
    }
}
