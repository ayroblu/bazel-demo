export function createWorkerPool<T>({ poolSize }: { poolSize: number }) {
  let occupied = 0;
  const pending = LinkedList<{
    task: () => Promise<T>;
    deferred: Deferred<T>;
  }>();
  function executeTask(task: () => Promise<T>): Promise<T> {
    const result = task();
    result.finally(() => {
      --occupied;
      const nextPending = pending.popStart();
      if (nextPending) {
        executeTask(nextPending.task).then(
          (value) => nextPending.deferred.resolve(value),
          (error) => nextPending.deferred.reject(error),
        );
      }
    });
    return result;
  }
  function addTask(task: () => Promise<T>): Promise<T> {
    if (++occupied < poolSize) {
      return executeTask(task);
    }
    const deferred = createDeferred<T>();
    pending.pushStart({ task, deferred });
    return deferred.promise;
  }
  return {
    addTask,
  };
}

type Deferred<T> = {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (reason: unknown) => void;
};
function createDeferred<T>(): Deferred<T> {
  let resolve: (value: T) => void = () => {};
  let reject = () => {};
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return {
    promise,
    resolve,
    reject,
  };
}
type LinkedListNode<T> = {
  value: T;
  next?: LinkedListNode<T> | undefined;
  prev?: LinkedListNode<T> | undefined;
};
function LinkedList<T>() {
  let start: LinkedListNode<T> | undefined;
  let end: LinkedListNode<T> | undefined;
  function pushStart(value: T) {
    const currentStart = start;
    start = {
      value,
      next: currentStart,
    };
    if (currentStart) {
      currentStart.prev = start;
    }
  }
  function pushEnd(value: T) {
    const currentEnd = end;
    end = {
      value,
      prev: currentEnd,
    };
    if (currentEnd) {
      currentEnd.next = end;
    }
  }
  function popStart(): T | undefined {
    const currentStart = start;
    start = currentStart?.next;
    if (start) {
      start.prev = undefined;
    }
    return currentStart?.value;
  }
  function popEnd(): T | undefined {
    const currentEnd = end;
    end = currentEnd?.prev;
    if (end) {
      end.next = undefined;
    }
    return currentEnd?.value;
  }
  return {
    pushStart,
    pushEnd,
    popStart,
    popEnd,
  };
}
