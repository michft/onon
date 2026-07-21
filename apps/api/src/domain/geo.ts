export interface Coordinate { latitude: number; longitude: number }

export function interpolateCoordinate(a: Coordinate, b: Coordinate, fraction: number): Coordinate {
  return {
    latitude: a.latitude + (b.latitude - a.latitude) * fraction,
    longitude: a.longitude + (b.longitude - a.longitude) * fraction
  };
}

export function bearingDegrees(a: Coordinate, b: Coordinate): number {
  const lat1 = a.latitude * Math.PI / 180;
  const lat2 = b.latitude * Math.PI / 180;
  const longitudeDelta = (b.longitude - a.longitude) * Math.PI / 180;
  const y = Math.sin(longitudeDelta) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(longitudeDelta);
  return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
}

export function offsetCoordinate(point: Coordinate, bearing: number, distanceM: number): Coordinate {
  const earthRadiusM = 6_378_137;
  const angularDistance = distanceM / earthRadiusM;
  const angle = bearing * Math.PI / 180;
  const latitude = point.latitude * Math.PI / 180;
  const longitude = point.longitude * Math.PI / 180;
  const targetLatitude = Math.asin(
    Math.sin(latitude) * Math.cos(angularDistance) + Math.cos(latitude) * Math.sin(angularDistance) * Math.cos(angle)
  );
  const targetLongitude = longitude + Math.atan2(
    Math.sin(angle) * Math.sin(angularDistance) * Math.cos(latitude),
    Math.cos(angularDistance) - Math.sin(latitude) * Math.sin(targetLatitude)
  );
  return { latitude: targetLatitude * 180 / Math.PI, longitude: targetLongitude * 180 / Math.PI };
}
