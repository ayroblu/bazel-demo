package com.example

import org.junit.Assert.assertEquals
import org.junit.Test
import uniffi.example.printAndAdd

class BridgeTests {
  @Test
  fun `printAndAdd returns 3`() {
    assertEquals(3, printAndAdd(1, 2))
  }
}
