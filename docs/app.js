const promptElement = document.querySelector('#agent-prompt code');
const statusElement = document.querySelector('#copy-status');
const copyButtons = [...document.querySelectorAll('[data-copy-prompt]')];

async function copySetupPrompt(button) {
  if (!promptElement) return;

  const originalLabel = button.textContent;
  try {
    await navigator.clipboard.writeText(promptElement.textContent.trim());
    copyButtons.forEach((item) => {
      item.textContent = 'Copied';
      item.setAttribute('data-copied', 'true');
    });
    if (statusElement) statusElement.textContent = 'Setup prompt copied.';
  } catch {
    if (statusElement) {
      statusElement.textContent = 'Clipboard access was blocked. Select the prompt below to copy it.';
      statusElement.classList.add('is-error');
    }
    promptElement.parentElement?.focus();
  }

  window.setTimeout(() => {
    copyButtons.forEach((item) => {
      item.textContent = item === button ? originalLabel : item.closest('.prompt-toolbar') ? 'Copy prompt' : 'Copy agent setup prompt';
      item.removeAttribute('data-copied');
    });
  }, 2200);
}

copyButtons.forEach((button) => {
  button.addEventListener('click', () => copySetupPrompt(button));
});
