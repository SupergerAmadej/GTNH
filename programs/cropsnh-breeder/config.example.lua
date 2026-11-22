return {
  -- Seconds to give an occupied crossing tile before clearing a stalled crop.
  retrySeconds = 600,

  -- Distance to the first center and between centers, in blocks.
  firstPlot = 4,
  plotSpacing = 4,

  -- Plots are 4, 8, 12, ... blocks ahead of the dock with the settings above.
  -- Directions are relative to the way the robot faces at the dock.
  -- Parent names are CropsNH crop IDs. The optional label is also accepted on the command line.
  plots = {
    {
      crop = "bonsaiOak",
      label = "Oak Bonsai",
      parents = {left = "wheat", right = "brownMushroom"},
    },
    {
      crop = "bonsaiBirch",
      label = "Birch Bonsai",
      parents = {left = "bonsaiOak", right = "sugarCane"},
    },
    {
      crop = "bonsaiBirch",
      label = "Birch Bonsai",
      stats = true, -- Only the left parent is planted. Prepare it and the center for Birch Bonsai.
    },
  },
}
