---------------------
-- Local Variables --
---------------------

-- Distance between pathfinding nodes
local PATH_NODE_DIST = 5
local PATH_NODE_DIST_SQ = 25

---------------------
-- Local Functions --
---------------------

-- Makes a 2int coordinate
-- @param x : x val of coordinate
-- @param y : y val of coodinate
-- @return  : 2int coordinate table:
--       .x : x val of coordinate
--       .y : y val of coordinate
--       .dist : distance along path to coordinate
local makeCoord = function(x, y, dist)
	return 	{
				x = x,
				y = y,
				dist = dist or 0
			}
end

-- Converts a 2int coordinate to Vector3
-- @param origin : The origin of the coordinate system
-- @param coord  : coordinate to convert
-- @return       : the Vector3 in world space corresponding to the given coordinate
local coordToPoint = function(origin, coord)
	return Vector3	(
						origin.x + (coord.x * PATH_NODE_DIST),
						0,
						origin.z + (coord.y * PATH_NODE_DIST)
					)
end

-- Tracks which coordinates have been visited
-- @param coordTracker : Table to track coordinates in
-- @param coord        : coordinate to track
-- @return             : true if the given coordinate's dist is smaller than the stored one
--                     : false otherwise
local trackCoord = function(coordTracker, coord)
	-- Place x if necessary
	if coordTracker[coord.x] == nil then
		coordTracker[coord.x] = {}
	end
	
	-- Return true if coordinate has not been tracked
	local unique = coordTracker[coord.x][coord.y] == nil
	coordTracker[coord.x][coord.y] = true
	return unique
	
	---- Better coordinates
	--if coordTracker[coord.x][coord.y] == nil or
	--   coordTracker[coord.x][coord.y].dist > coord.dist
	--then
	--	coordTracker[coord.x][coord.y] = coord
	--	return true
	--end
	--
	---- Worse coordinate
	--return false
end

-- Constructs a nativePath from a finishedPath
-- @param finishedPath : The finished path
-- @return             : The same path, stored in native format
local makeNativePath = function(finishedPath, origin)
	-- Convert final path to the game's native format
	-- Structure: table
	-- .steps
	--       .1.y = 0
	--       .1.x = <x value>
	--       .1.z = <z value>
	--       ...
	local nativePath = { steps = {} }
	
	for i=1,table.getn(finishedPath),1 do
		local worldVec = coordToPoint(origin, finishedPath[i])
		local point =
		{
			y = worldVec.y,
			x = worldVec.x,
			z = worldVec.z
		}
	
		nativePath.steps[i] = point
	end
	
	return nativePath
end

------------------------
-- External Functions --
------------------------

-- @param startPos : A Vector3 containing the starting position in world units
-- @param endPos   : A Vector3 continaing the ending position in world units
-- @param pathcaps : (Optional) the pathcaps to use for pathfinding
-- @return         : A partial path object
--                 .nativePath : If path is finished via LOS, this will be populated, otherwise nil
local requestPath = function(startPos, endPos, pathcaps)
	
	----------------------
	-- Store parameters --
	----------------------
	local path = { }
	
	-- Store start/end in 2D Space
	path.startPos = startPos
	path.endPos   = endPos
	path.startPos.y = 0
	path.endPos.y = 0
	
	-- LOS parameter
	if pathcaps == nil then
		path.pathcaps = { ignoecreep = false, ignorewalls = false }
	else
		path.pathcaps = pathcaps
	end
	
	-- Coordinate tracker
	path.coordTracker = { }
	
	-------------------------
	-- Prepare Pathfinding --
	-------------------------
	
	-- Has LOS, return line
	if TheWorld.Pathfinder:IsClear	(
											path.startPos.x, path.startPos.y, path.startPos.z,
											path.endPos.x,   path.endPos.y,   path.endPos.z,
											path.pathcaps
										)
	then
		-- Convert start position
		path.nativePath = makeNativePath({ makeCoord(0, 0) }, path.startPos)
		
		
		-- Last step is to endPos
		local endStep = 
		{
			y = path.endPos.y,
			x = path.endPos.x,
			z = path.endPos.z
		}
		table.insert(path.nativePath.steps, endStep)
	
	-- No LOS, prepare pathfinding
	else
		-- Finished path and distance
		path.finishedPath = nil
		
		-- Paths to process
		trackCoord(path.coordTracker, makeCoord(0,0))
		path.paths = { { makeCoord(0,0) } }
		
		
		-- Future paths to process
		path.newPaths = { }
		
		-- The index in path.paths to start processing at
		path.nextWork = 1
	end
	
	-- Partial path constructed
	return path
end

-- @param path : The partial path to finish (request one via requestPath)
-- @param work : The number of paths to test
-- @return     : true if path is finished (access via path.nativePath - path.nativePath.steps IS NIL IF NO PATH IS FOUND), otherwise false
local processPath = function(path, work)

	-- Path already found, return
	if path.nativePath ~= nil then
		return true
	end
	
	-- Cache parameters
	local origin = path.startPos
	
	-- Paths processed this run
	local workDone = 0
	
	-- Process until finished (no path.paths remain or a path is found)
	while table.getn(path.paths) > 0 and path.finishedPath == nil do
	
		-- Iterate all path.paths
		local pathSize = table.getn(path.paths)
		local p = path.nextWork
		while p <= pathSize and path.finishedPath == nil do
		
			-- Path to Process
			local currentPath = path.paths[p]
			
			-- Process if better case than the finished path, or if we don't have a finished path yet
			local lastPoint = currentPath[table.getn(currentPath)]
			local worldPoint_Last = coordToPoint(origin, lastPoint)
		
			-- Candidate points
			local candidatePoints = 	{
											makeCoord(lastPoint.x    , lastPoint.y + 1),
											makeCoord(lastPoint.x + 1, lastPoint.y),
											makeCoord(lastPoint.x - 1, lastPoint.y),
											makeCoord(lastPoint.x    , lastPoint.y - 1),
										}
			
			-- Process Candidates
			for point=1,4,1 do
			
				-- Calculate distance
				local worldPoint_Candidate = coordToPoint(origin, candidatePoints[point])
				candidatePoints[point].dist = worldPoint_Candidate:Dist(worldPoint_Last) + lastPoint.dist
				
				-- Prcess candidate only if it's the best path on record, and it has LOS to previous point
				if trackCoord(path.coordTracker, candidatePoints[point]) and
					TheWorld.Pathfinder:IsClear	(
													worldPoint_Last.x, worldPoint_Last.y, worldPoint_Last.z,
													worldPoint_Candidate.x, worldPoint_Candidate.y, worldPoint_Candidate.z,
													path.pathcaps
												)
				then
					
					-- Construct new path
					local newPath = { unpack(currentPath) }
					table.insert(newPath, candidatePoints[point])
					
					-- Final path located
					if worldPoint_Candidate:DistSq(path.endPos) < PATH_NODE_DIST_SQ then
						path.finishedPath = newPath
					
					-- Continue path finding
					else
						table.insert(path.newPaths, newPath)
					end
					
					-- Update work done
					workDone = workDone + 1
				end
			end
			
			-- Next path
			p = p + 1
			
			-- Check work
			if workDone >= work then
				path.nextWork = p
				return false
			end
		end
		
		-- Update path.paths
		path.paths = path.newPaths
		path.newPaths = {}
		path.nextWork = 1
	end
	
	----------------------------
	-- Pathfinding finished!! --
	----------------------------
	
	-- No path found (well this is awkard given the giant banner....)
	if path.finishedPath == nil then
		path.nativePath = { }
		return true
	else
		path.nextWork = 2
	end
	
	-- Smooth edges
	-- ie: {0,0}, {0,2}, {3,2} -> {0,0}, {3,2} (given LOS)
	local c = path.nextWork
	while c + 1 < table.getn(path.finishedPath) do
    
		-- Points to test
		local p0 = coordToPoint(path.startPos, path.finishedPath[c-1])
		local p1 = coordToPoint(path.startPos, path.finishedPath[c+1])
		
		-- Has LOS
		if TheWorld.Pathfinder:IsClear	(
											p0.x, p0.y, p0.z,
											p1.x, p1.y, p1.z,
											path.pathcaps
										)
		then
			table.remove(path.finishedPath, c)
		
		-- No LOS
		else
			c = c + 1
		end
		
		-- Update work done
		workDone = workDone + 1
		if workDone >= work then
			path.nextWork = c
			return false
		end
	end
	
	-- Convert to native path
	path.nativePath = makeNativePath(path.finishedPath, path.startPos)
	
	
	-- Last step is to endPos
	local endStep = 
	{
		y = path.endPos.y,
		x = path.endPos.x,
		z = path.endPos.z
	}
	table.insert(path.nativePath.steps, endStep)
	
	---- Debugging
	--print("Path Finished [" .. table.getn(path.nativePath) .. "][" .. table.getn(path.nativePath.steps) .. "]")
	--
	--for k,v in pairs(path.nativePath) do
	--	for k2,v2 in pairs(v) do
	--		for k3,v3 in pairs(v2) do
	--		
	--			print("nativePath." .. k .. "." .. k2 .. "." .. k3 .. " = " .. v3)
	--		
	--		end
	--	end
	--end
	
	-- Return Success
	return true
end

return
{
	requestPath = requestPath,
	processPath = processPath
}