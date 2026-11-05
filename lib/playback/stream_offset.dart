/// Whether a seek to [target] in a transcoded stream must start the stream again on the server, for servers with the OpenSubsonic `transcodeOffset` extension.
///
/// A transcoded stream has no byte ranges, so the player can only seek inside what it has already received. The stream began at [offset] in the song, and [buffered] of it has arrived. Inside that stretch the player seeks itself; anywhere else, and before the start of the stream, the server starts again at [target]. Without [restartable] the player seeks itself in every case.
bool restartsStream({
  required Duration target,
  required Duration offset,
  required Duration buffered,
  required bool restartable,
}) {
  if (!restartable) return false;
  return target < offset || target > offset + buffered;
}
