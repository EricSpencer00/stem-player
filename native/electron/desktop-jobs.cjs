function createJobRunner(options) {
  let running = false;
  const idleResolvers = new Set();

  function resolveIdle() {
    for (const resolve of idleResolvers) resolve();
    idleResolvers.clear();
  }

  async function pump() {
    if (running) return;
    running = true;

    try {
      while (true) {
        const nextJob = options.getNextJob();
        if (!nextJob) break;
        await options.runJob(nextJob);
      }
    } finally {
      running = false;
      if (!options.getNextJob()) {
        resolveIdle();
      }
    }
  }

  function schedule() {
    setImmediate(() => {
      pump().catch((error) => {
        if (typeof options.onError === 'function') {
          options.onError(error);
        }
      });
    });
  }

  return {
    schedule,
    waitForIdle() {
      if (!running && !options.getNextJob()) {
        return Promise.resolve();
      }
      return new Promise((resolve) => {
        idleResolvers.add(resolve);
      });
    },
  };
}

module.exports = {
  createJobRunner,
};
